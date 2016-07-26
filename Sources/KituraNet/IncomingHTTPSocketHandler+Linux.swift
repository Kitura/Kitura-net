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

import Foundation
import Glibc

import LoggerAPI
import Socket

/// Linux Specific extension of the IncomingHTTPSocketHandler class.
extension IncomingHTTPSocketHandler {
    
    /// Perform platform specfic setup, invoked by the init function
    func setup() { }
    
    /// Close the socket and mark this handler as no longer in progress.
    ///
    /// **Note:** Closing the socket causes it to be dropped by epoll.
    func close() {
        if  socket.socketfd > -1 {
            socket.close()
        }
        inProgress = false
        keepAliveUntil = 0.0
    }
}

#endif
