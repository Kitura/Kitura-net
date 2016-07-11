/**
 * Copyright IBM Corporation 2016
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
 **/


#if os(Linux)

import Glibc
import Foundation

import CEpoll
import KituraSys
import LoggerAPI
import Socket

class IncomingSocketManager  {
    
    private let maximumNumberOfEvents = 300
    
    private let epollDescriptor: Int32
    private let epollTimeout: Int32 = 50
    
    private let queue = Queue(type: .serial, label: "LinuxIncomingSocketManager")
    
    private var keepOnRunning = true
    
    private var socketHandlers = [Int32: IncomingHTTPSocketHandler]()
    
    init() {
        epollDescriptor = epoll_create1(0)
        
        queue.enqueueAsynchronously() { [unowned self] in self.process() }
    }
    
    ///
    /// Handle a new incoming socket
    ///
    /// - Parameter socket: the incoming socket to handle
    /// - Parameter using: The ServerDelegate to actually handle the socket
    ///
    func handle(socket: Socket, using delegate: ServerDelegate) {
        
        do {
            try socket.setBlocking(mode: false)
        }
        catch {
            print("Failed to make incoming socket (File Descriptor=\(socket.socketfd)) non-blocking. Error code=\(errno). Reason=\(lastError())")
            Log.error("Failed to make incoming socket (File Descriptor=\(socket.socketfd)) non-blocking. Error code=\(errno). Reason=\(lastError())")
        }
        
        let handler = IncomingHTTPSocketHandler(socket: socket, using: delegate)
        socketHandlers[socket.socketfd] = handler
        
        var event = epoll_event()
        event.events = EPOLLIN.rawValue | EPOLLET.rawValue
        event.data.fd = socket.socketfd
        let result = epoll_ctl(epollDescriptor, EPOLL_CTL_ADD, handler.fileDescriptor, &event);
        if  result == -1  {
            Log.error("epoll_ctl failure. Error code=\(errno). Reason=\(lastError())")
            print("epoll_ctl failure. Error code=\(errno). Reason=\(lastError())")
        }
    }
    
    ///
    /// Wait and process the ready events
    ///
    private func process() {
        var pollingEvents = [epoll_event](repeating: epoll_event(), count: maximumNumberOfEvents)
        
        while  keepOnRunning  {
            let count = Int(epoll_wait(epollDescriptor, &pollingEvents, Int32(maximumNumberOfEvents), epollTimeout))
            
            if  count == -1  {
                Log.error("epollWait failure. Error code=\(errno). Reason=\(lastError())")
                print("epollWait failure. Error code=\(errno). Reason=\(lastError())")
                continue
            }
                
            if  count == 0  {
                continue
            }
            
            for  index in 0  ..< count {
                let event = pollingEvents[index]
                
                if  (event.events & EPOLLERR.rawValue)  == 1  ||  (event.events & EPOLLHUP.rawValue) == 1  ||  (event.events & EPOLLIN.rawValue) == 0 {
                    
                    print("Error occurred on a file descriptor of an epool wait")
                    
                }
                else {
                    if  let handler = socketHandlers[event.data.fd] {
                        handler.process()
                    }
                    else {
                        print("No handler for file descriptor \(event.data.fd)")
                    }
                }
            }
        }
    }
    
    
    ///
    /// Private method to return the last error based on the value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    ///
    private func lastError() -> String {
        
        return String(validatingUTF8: strerror(errno)) ?? "Error: \(errno)"
    }
}

#endif
