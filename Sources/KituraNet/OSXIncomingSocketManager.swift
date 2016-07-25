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

#if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)

import Foundation
   
import LoggerAPI
import Socket
    
/// The IncomingSocketManager class is in charge of managing all of the incoming sockets.
/// In particular, it is in charge of:
///   1. Creating and managing the IncomingHTTPSocketHandlers (one per incomng socket)
///   2. Cleaning up idle sockets, when new incoming sockets arrive.
class IncomingSocketManager  {
    
    private var socketHandlers = [Int32: IncomingHTTPSocketHandler]()
        
    /// Interval at which to check for idle sockets to close
    let keepAliveIdleCheckingInterval: TimeInterval = 60.0
    
    /// The last time we checked for an idle socket
    var keepAliveIdleLastTimeChecked = Date()
    
    /// Handle a new incoming socket
    ///
    /// - Parameter socket: The incoming socket to handle
    /// - Parameter using: The ServerDelegate to actually handle the socket
    func handle(socket: Socket, using: ServerDelegate) {
        
        do {
            try socket.setBlocking(mode: false)
            
            let handler = IncomingHTTPSocketHandler(socket: socket, using: using)
            socketHandlers[socket.socketfd] = handler
        }
        catch {
            Log.error("Failed to make incoming socket (File Descriptor=\(socket.socketfd)) non-blocking. Error code=\(errno). Reason=\(lastError())")
        }
        
        removeIdleSockets()
    }
    
    /// Clean up idle sockets by:
    ///   1. Removing the reference to the IncomingHTTPSocketHandler
    ///   2. Have the IncomingHTTPSocketHandler close the socket
    ///
    /// **Note:** In order to safely update the socketHandlers Dictionary the removal
    /// of idle sockets is done in the thread that is accepting new incoming sockets
    /// after a socket was accepted. Had this been done in a timer, there would be a
    /// to have a lock around the access to the socketHandlers Dictionary. The other
    /// idea here is that if sockets aren't coming in, it doesn't matter too much if
    /// we leave a round some idle sockets.
    private func removeIdleSockets() {
        let now = Date()
        guard  now.timeIntervalSince(keepAliveIdleLastTimeChecked) > keepAliveIdleCheckingInterval  else { return }
            
        let maxInterval = now.timeIntervalSinceReferenceDate
        for (fileDescriptor, handler) in socketHandlers {
            if  handler.inProgress  ||  maxInterval < handler.keepAliveUntil {
                continue
            }
            socketHandlers.removeValue(forKey: fileDescriptor)
            handler.close()
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

#endif
