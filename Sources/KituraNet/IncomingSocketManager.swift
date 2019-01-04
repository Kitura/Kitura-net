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

// Holder for a processor thread's socketHandlers dictionary, as a buffer between
// the dictionary itself and the outer one that associates each dictionary with an
// epoll FD. This is an attempt to prevent a crash which may be related to
// dictionary modification on different threads in Swift 5.
fileprivate class SocketHandlerContainer: Equatable, Hashable {

    var handlers: [Int32: IncomingSocketHandler]
    let id: Int

    init(id: Int) {
        self.id = id
        self.handlers = [Int32: IncomingSocketHandler]()
    }

    static func == (lhs: SocketHandlerContainer, rhs: SocketHandlerContainer) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

}

/**
The IncomingSocketManager class is in charge of managing all of the incoming sockets.
In particular, it is in charge of:
  1. On Linux when no special compile options are specified:
      a. Creating the epoll handle
      b. Adding new incoming sockets to the epoll descriptor for read events
      c. Running the "thread" that does the epoll_wait
  2. Creating and managing the IncomingSocketHandlers and IncomingHTTPDataProcessors
     (one pair per incoming socket)
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
    
    /// A number of mappings from socket file descriptor to IncomingSocketHandler.
    /// On Linux with epoll, there is one dictionary per epoll thread. Otherwise,
    /// there is a single dictionary at index 0.
    private var socketHandlers: [Int32: SocketHandlerContainer]

    /// The sum total of handlers across all epoll threads.
    /// Used by SocketManagerTests to check number of registered handlers.
    var socketHandlerCount: Int {
        return socketHandlers.reduce(0, { i, handlerTuple in
            i + handlerTuple.1.handlers.count
        })
    }
    
    /// Interval at which to check for idle sockets to close
    let keepAliveIdleCheckingInterval: TimeInterval = 5.0
    
    /// The last time we checked for an idle socket
    var keepAliveIdleLastTimeChecked = Date()

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
            var epollDescriptors = [Int32]()
            var queues = [DispatchQueue]()
            var socketHandlers = [Int32: SocketHandlerContainer]()
            for i in 0 ..< numberOfEpollTasks {
                // Note: The parameter to epoll_create is ignored on modern Linux's
                let epollFd = epoll_create(100)
                epollDescriptors.append(epollFd)
                queues.append(DispatchQueue(label: "IncomingSocketManager\(i)"))
                // socketHandlers is split into a separate dictionary for each epoll thread.
                socketHandlers[epollFd] = SocketHandlerContainer(id: Int(epollFd))
            }
            self.epollDescriptors = epollDescriptors
            self.queues = queues
            self.socketHandlers = socketHandlers

            for i in 0 ..< numberOfEpollTasks {
                let epollDescriptor = epollDescriptors[i]

                queues[i].async() { [weak self] in
                    // server could be stopped and socketManager deallocated before this is run.
                    self?.process(epollDescriptor: epollDescriptor)
                }
            }
        }
    #else
    /**
     IncomingSocketManager initializer
     */
        public init() {
           // socketHandlers is not split across threads.
           self.socketHandlers = [Int32: SocketHandlerContainer]() 
           self.socketHandlers[0] = SocketHandlerContainer(id: 0)
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
            for index in socketHandlers.keys {
                removeIdleSockets(socketHandlerIndex: index, removeAll: true)
            }
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
        // With epoll, we must split the socket handler dictionary so that each
        // epoll thread has a separate dictionary.
        #if !GCD_ASYNCH && os(Linux)
            let socketHandlerIndex: Int32 = epollDescriptor(fd: socket.socketfd)
        #else
            let socketHandlerIndex: Int32 = 0
        #endif
        guard socketHandlers[socketHandlerIndex] != nil else {
            Log.error("Unable to locate socketHandlers index \(socketHandlerIndex) (socketfd: \(socket.socketfd))")
            return
        }

        do {
            try socket.setBlocking(mode: false)
            
            let handler = IncomingSocketHandler(socket: socket, using: processor)
            socketHandlers[socketHandlerIndex]?.handlers[socket.socketfd] = handler
            
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
        
        removeIdleSockets(socketHandlerIndex: socketHandlerIndex)
    }
    
    #if !GCD_ASYNCH && os(Linux)
        /// Wait and process the ready events by invoking the IncomingHTTPSocketHandler's hndleRead function
    private func process(epollDescriptor:Int32) {
            var pollingEvents = [epoll_event](repeating: epoll_event(), count: maximumNumberOfEvents)
            var deferredHandlers = [Int32: IncomingSocketHandler]()
            var deferredHandlingNeeded = false
            guard socketHandlers[epollDescriptor] != nil else {
                Log.error("Unable to locate socketHandlers for epollfd \(epollDescriptor)")
                return
            }
        
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
                        if  let handler = socketHandlers[epollDescriptor]?.handlers[event.data.fd] {
    
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
    
                // Handle any deferred processing of read data
                if deferredHandlingNeeded {
                    deferredHandlingNeeded = process(deferredHandlers: &deferredHandlers)
                }
            }

            // cleanup after manager stopped
            removeIdleSockets(socketHandlerIndex: epollDescriptor, removeAll: true)
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
    /// **Note:** In order to safely update the socketHandlers Dictionary the removal
    /// of idle sockets is done in the thread that is accepting new incoming sockets
    /// after a socket was accepted. Had this been done in a timer, there would be a
    /// to have a lock around the access to the socketHandlers Dictionary. The other
    /// idea here is that if sockets aren't coming in, it doesn't matter too much if
    /// we leave a round some idle sockets.
    ///
    /// - Parameter allSockets: flag indicating if the manager is shutting down, and we should cleanup all sockets, not just idle ones
    private func removeIdleSockets(socketHandlerIndex: Int32, removeAll: Bool = false) {
        let now = Date()
        guard removeAll || now.timeIntervalSince(keepAliveIdleLastTimeChecked) > keepAliveIdleCheckingInterval  else { return }
        guard socketHandlers[socketHandlerIndex] != nil else {
            Log.error("Unable to locate socketHandlers for index \(socketHandlerIndex)")
            return
        }
        let maxInterval = now.timeIntervalSinceReferenceDate
        socketHandlers[socketHandlerIndex]?.handlers.forEach { (fileDescriptor, handler) in 
            if !removeAll && handler.processor != nil  &&  (handler.processor?.inProgress ?? false  ||  maxInterval < handler.processor?.keepAliveUntil ?? maxInterval) {
                //continue
            } else {
                socketHandlers[socketHandlerIndex]?.handlers.removeValue(forKey: fileDescriptor)

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
        }
        keepAliveIdleLastTimeChecked = Date()
    }
    
    /// Private method to return the last error based on the value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    private func lastError() -> String {
        
        return String(validatingUTF8: strerror(errno)) ?? "Error: \(errno)"
    }
}

