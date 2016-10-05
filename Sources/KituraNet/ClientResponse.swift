/*
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
 */


import Foundation

// MARK: ClientResponse

/// This class describes the response sent by the remote server to an HTTP request
/// sent using the `ClientRequest` class. This class is an extension of the 
/// `HTTPIncomingMessage` class.
public class ClientResponse: HTTPIncomingMessage {
    
    /// Initializes a `ClientResponse` instance
    init() {
        
        super.init(isRequest: false)
        
    }
    
    /// The HTTP Status code, as an Int, sent in the response by the remote server.
    public internal(set) var status = -1 {
        
        didSet {
            statusCode = HTTPStatusCode(rawValue: status)!
        }
        
    }
    
    /// The HTTP Status code, as an `HTTPStatusCode`, sent in the response by the remote server.
    public internal(set) var statusCode: HTTPStatusCode = HTTPStatusCode.unknown
    
    /// BufferList instance for storing the response 
    var responseBuffers = BufferList()
    
    /// Parse the contents of the responseBuffers
    func parse() -> HTTPParserStatus {
        let buffer = NSMutableData()
        _ = responseBuffers.fill(data: buffer)
        return super.parse(buffer)
    }
}
