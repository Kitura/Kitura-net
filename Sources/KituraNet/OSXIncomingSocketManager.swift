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
   
import Socket
    
class IncomingSocketManager  {
    
    private var socketHandlers = [Int32: IncomingHTTPSocketHandler]()
        
    ///
    /// Interval at which to check for idle sockets to close
    ///
    let keepAliveIdleCheckingInterval: TimeInterval = 60.0
        
    ///
    /// The last time we checked for an idle socket
    ///
    var keepAliveIdleLastTimeChecked = Date()
    
    ///
    /// Handle a new incoming socket
    ///
    /// - Parameter socket: The incoming socket to handle
    /// - Parameter using: The ServerDelegate to actually handle the socket
    ///
    func handle(socket: Socket, using: ServerDelegate) {
        let handler = IncomingHTTPSocketHandler(socket: socket, using: using)
        socketHandlers[socket.socketfd] = handler
        
        removeIdleSockets()
    }
        
    ///
    /// Remove idle sockets
    ///
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
}

#endif
