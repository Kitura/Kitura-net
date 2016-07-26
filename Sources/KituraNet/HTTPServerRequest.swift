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

// MARK: HTTPServerRequest

/// This class implements the ServerRequest protocol for incoming sockets that
/// are communicating via the HTTP protocol. Most of the implementation is in
/// the HTTPIncomingMessage class which implements logic common to this class
/// and the ClientResponse class.
public class HTTPServerRequest: HTTPIncomingMessage, ServerRequest {

    /// Reader for the request
    private let reader: PseudoSynchronousReader

    /// server IP address pulled from socket
    public var remoteAddress: String {
        return reader.remoteHostname
    }
    
    /// Initializes a HTTPServerRequest
    ///
    /// - Parameter socket: the socket
    init (reader: PseudoSynchronousReader) {
        
        self.reader = reader
        super.init(isRequest: true)
        
        setup(self)
    }
}

/// IncomingMessageHelper protocol extension
extension HTTPServerRequest: IncomingMessageHelper {
    
    /// "Read" data from the actual underlying transport
    ///
    /// - Parameter into: The NSMutableData that will be receiving the data read in.
    func readHelper(into data: NSMutableData) throws -> Int {

        let length = reader.read(into: data)
        return length 
    }
    
}
