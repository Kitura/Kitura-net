/*
 * Copyright IBM Corporation 2016, 2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


#if !GCD_ASYNCH && os(Linux)
    import Glibc
    import CEpoll
#endif

import Dispatch
import Foundation

import LoggerAPI
import Socket

/**
The IncomingSocketManager class is in charge of managing all of the incoming sockets.
In particular, it is in charge of:
  1. On Linux when no special compile options are specified:
      a. Creating the epoll handle
      b. Adding new incoming sockets to the epoll descriptor for read events
      c. Running the "thread" that does the epoll_wait
  2. Creating and managing the IncomingSocketHandlers and IncomingHTTPDataProcessors
     (one pair per incomng socket)
  3. Cleaning up idle sockets, when new incoming sockets arrive.

### Usage Example: ###
````swift
 //Create a manager to manage all of the incoming sockets.
 var manager: IncomingSocketManager?
 
 override func setUp() {
     manager = IncomingSocketManager()
 }
````
*/
public class IncomingSocketManager  {
    
    /// A mapping from socket file descriptor to IncomingSocketHandler
    private var socketHandlers = [Int32: IncomingSocketHandler]()
    private var shQueue = DispatchQueue(label: "socketHandlers.queue", attributes: .concurrent)

    internal var socketHandlerCount: Int {
        var result: Int = 0
        shQueue.sync {
            result = socketHandlers.count
        }
        return result
    }

    /// Interval at which to check for idle sockets to close
    let keepAliveIdleCheckingInterval: TimeInterval = 5.0
    
    /// The last time we checked for an idle socket
    var keepAliveIdleLastTimeChecked = Date()

    /// Defines the limit on the size of requests. This may be modified by the user at runtime.
    var serverOptions: ServerOptions = ServerOptions()

    /// Flag indicating when we are done using this socket manager, so we can clean up
    private var stopped = false

    #if !GCD_ASYNCH && os(Linux)
        private let maximumNumberOfEvents = 300
    
        private let numberOfEpollTasks = 2 // todo - this tuning parameter should be revisited as Kitura and libdispatch mature

        private let epollDescriptors:[Int32]
        private let queues:[DispatchQueue]

        let epollTimeout: Int32 = 50

        private func epollDescriptor(fd:Int32) -> Int32 {
            return epollDescriptors[Int(fd) % numberOfEpollTasks];
        }

    
    /**
     IncomingSocketManager initializer
     */
        public init() {
            var t1 = [Int32]()
            var t2 = [DispatchQueue]()
            for i in 0 ..< numberOfEpollTasks {
                // Note: The parameter to epoll_create is ignored on modern Linux's
                t1 += [epoll_create(100)]
                t2 += [DispatchQueue(label: "IncomingSocketManager\(i)")]
            }
            epollDescriptors = t1
            queues = t2

            for i in 0 ..< numberOfEpollTasks {
                // Only run removeIdleSockets in the first instance of process.
                let runRemoveIdleSockets = (i == 0)
                let epollDescriptor = epollDescriptors[i]

                queues[i].async() { [weak self] in
                    // server could be stopped and socketManager deallocated before this is run.
                    self?.process(epollDescriptor: epollDescriptor, runRemoveIdleSockets: runRemoveIdleSockets)
                }
            }
        }
    #else
    /**
     IncomingSocketManager initializer
     */
        public init(connectionPolicy: ServerOptions = ServerOptions()) {
            self.serverOptions = connectionPolicy
        }
    #endif

    deinit {
        stop()
    }

    /**
     Stop this socket manager instance and cleanup resources.
     If using epoll, it also ends the epoll process() task, closes the epoll fd and releases its thread.
     
     ### Usage Example: ###
     ````swift
     socketManager?.stop()
     ````
     */
    public func stop() {
        stopped = true
        #if GCD_ASYNCH || !os(Linux)
            removeIdleSockets(removeAll: true)
        #endif
    }
    
    /**
     Handle a new incoming socket
     
     - Parameter socket: the incoming socket to handle
     - Parameter using: The ServerDelegate to actually handle the socket
     
     ### Usage Example: ###
     ````swift
     processor?.handler = handler
     ````
     */
    public func handle(socket: Socket, processor: IncomingSocketProcessor) {
        guard !stopped else {
            Log.warning("Cannot handle socket as socket manager has been stopped")
            return
        }

        do {
            try socket.setBlocking(mode: false)
            
            let handler = IncomingSocketHandler(socket: socket, using: processor, options: self.serverOptions)
            shQueue.sync(flags: .barrier) {
                socketHandlers[socket.socketfd] = handler
            }
            
            #if !GCD_ASYNCH && os(Linux)
                var event = epoll_event()
                event.events = EPOLLIN.rawValue | EPOLLOUT.rawValue | EPOLLET.rawValue
                event.data.fd = socket.socketfd
                let result = epoll_ctl(epollDescriptor(fd: socket.socketfd), EPOLL_CTL_ADD, socket.socketfd, &event)
                if  result == -1  {
                    Log.error("epoll_ctl failure. Error code=\(errno). Reason=\(lastError())")
                }
            #endif
        }
        catch let error {
            Log.error("Failed to make incoming socket (File Descriptor=\(socket.socketfd)) non-blocking. Error = \(error)")
        }
        
        removeIdleSockets()
    }
    
    #if !GCD_ASYNCH && os(Linux)
        /// Wait and process the ready events by invoking the IncomingHTTPSocketHandler's hndleRead function
    private func process(epollDescriptor:Int32, runRemoveIdleSockets: Bool) {
            var pollingEvents = [epoll_event](repeating: epoll_event(), count: maximumNumberOfEvents)
            var deferredHandlers = [Int32: IncomingSocketHandler]()
            var deferredHandlingNeeded = false
        
            while !stopped {
                let count = Int(epoll_wait(epollDescriptor, &pollingEvents, Int32(maximumNumberOfEvents), epollTimeout))
    
                if stopped {
                    // If stopped was set while we were waiting for epoll, quit now
                    break
                }
    
                if  count == -1  {
                    Log.error("epollWait failure. Error code=\(errno). Reason=\(lastError())")
                    continue
                }
                
                if  count == 0  {
                    if deferredHandlingNeeded {
                        deferredHandlingNeeded = process(deferredHandlers: &deferredHandlers)
                    }
                    continue
                }
            
                for  index in 0  ..< count {
                    let event = pollingEvents[index]
                
                    if  (event.events & EPOLLERR.rawValue)  == 1  ||  (event.events & EPOLLHUP.rawValue) == 1  ||
                                (event.events & (EPOLLIN.rawValue | EPOLLOUT.rawValue)) == 0 {
                    
                        Log.error("Error occurred on a file descriptor of an epool wait")
                    } else {
                        shQueue.sync {
                            if  let handler = socketHandlers[event.data.fd] {
                                if  (event.events & EPOLLOUT.rawValue) != 0 {
                                    handler.handleWrite()
                                }
                                if  (event.events & EPOLLIN.rawValue) != 0 {
                                    let processed = handler.handleRead()
                                    if !processed {
                                        deferredHandlingNeeded = true
                                        deferredHandlers[event.data.fd] = handler
                                    }
                                }
                            }
                            else {
                                Log.error("No handler for file descriptor \(event.data.fd)")
                            }
                        }
                    }
                }
    
                // Handle any deferred processing of read data
                if deferredHandlingNeeded {
                    deferredHandlingNeeded = process(deferredHandlers: &deferredHandlers)
                }
            }

            // cleanup after manager stopped
            if runRemoveIdleSockets {
                removeIdleSockets(removeAll: true)
            }
            close(epollDescriptor)
        }

        private func process(deferredHandlers: inout [Int32: IncomingSocketHandler]) -> Bool {
            var result = false

            for (fileDescriptor, handler) in deferredHandlers {
                let processed = handler.handleBufferedReadDataHelper()
                if processed {
                    deferredHandlers.removeValue(forKey: fileDescriptor)
                }
                else {
                    result = true
                }
            }
            return result
        }
    #endif
    
    /// Clean up idle sockets by:
    ///   1. Removing them from the epoll descriptor
    ///   2. Removing the reference to the IncomingHTTPSocketHandler
    ///   3. Have the IncomingHTTPSocketHandler close the socket
    ///
    /// - Parameter removeAll: flag indicating if the manager is shutting down, and we should cleanup all sockets, not just idle ones
    /// - Parameter runNow: indicates that the removal should be performed immediately, rather than at the next scheduled interval
    internal func removeIdleSockets(removeAll: Bool = false, runNow: Bool = false) {
        let now = Date()
        guard removeAll || runNow || now.timeIntervalSince(keepAliveIdleLastTimeChecked) > keepAliveIdleCheckingInterval  else { return }
        shQueue.sync(flags: .barrier) {
            let maxInterval = now.timeIntervalSinceReferenceDate
            for (fileDescriptor, handler) in socketHandlers {
                if !removeAll && handler.processor != nil  &&  (handler.processor?.inProgress ?? false  ||  maxInterval < handler.processor?.keepAliveUntil ?? maxInterval) {
                    continue
                }
                socketHandlers.removeValue(forKey: fileDescriptor)

                #if !GCD_ASYNCH && os(Linux)
                    let result = epoll_ctl(epollDescriptor(fd: fileDescriptor), EPOLL_CTL_DEL, fileDescriptor, nil)
                    if result == -1 {
                        if errno != EBADF &&     // Ignore EBADF error (bad file descriptor), probably got closed.
                               errno != ENOENT { // Ignore ENOENT error (No such file or directory), probably got closed.
                            Log.error("epoll_ctl failure. Error code=\(errno). Reason=\(lastError())")
                        }
                    }
                #endif

                handler.prepareToClose()
            }
            keepAliveIdleLastTimeChecked = Date()
        }
    }
    
    /// Private method to return the last error based on the value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    private func lastError() -> String {
        
        return String(validatingUTF8: strerror(errno)) ?? "Error: \(errno)"
    }
}

