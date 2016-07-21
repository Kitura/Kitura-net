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

import Dispatch
import Foundation


import LoggerAPI
import Socket

extension IncomingHTTPSocketHandler {
    
    
    ///
    /// Perform platform specfic setup, invoked by the init function
    ///
    func setup() {
        source = DispatchSource.read(fileDescriptor: socket.socketfd, queue: IncomingHTTPSocketHandler.socketReaderQueue)
        
        source!.setEventHandler() {
            self.handleRead()
        }
        
        source!.resume()
    }
    
    ///
    /// Close the socket
    ///
    func close() {
        source!.cancel()
        socket.close()
        inProgress = false
        keepAliveUntil = 0.0
    }
    
    
}

#endif
