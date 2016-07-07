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

import Foundation


// MARK: ServerRequest

public class ServerRequest: IncomingMessage {

    ///
    /// Reader for the request
    ///
    private let reader: PseudoAsynchronousReader

    ///
    /// server IP address pulled from socket
    ///
    public var remoteAddress: String {
        return reader.remoteHostname
    }
    
    ///
    /// Initializes a ServerRequest
    ///
    /// - Parameter socket: the socket 
    ///
    init (reader: PseudoAsynchronousReader) {
        
        self.reader = reader
        super.init(isRequest: true)
        
        setup(self)
    }
}

/// IncomingMessageHelper protocol extension
extension ServerRequest: IncomingMessageHelper {
    
    ///
    /// TODO: ???
    ///
    func readHelper(into data: NSMutableData) throws -> Int {

        let length = reader.readSynchronously(into: data)
        return length
    }
    
}
