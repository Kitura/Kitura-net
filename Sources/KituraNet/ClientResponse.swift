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

// MARK: ClientResponse

public class ClientResponse: HTTPIncomingMessage {
    
    /// Initializes a ClientResponse instance
    ///
    /// - Returns: a ClientResponse instance
    init() {
        
        super.init(isRequest: false)
        setup(self)
        
    }
    
    /// HTTP Status code
    public internal(set) var status = -1 {
        
        didSet {
            statusCode = HTTPStatusCode(rawValue: status)!
        }
        
    }
    
    /// HTTP Status code
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


// MARK: protocol extension for IncomingMessageHelper

extension ClientResponse: IncomingMessageHelper {
    
    ///
    ///  Calls the response buffer to fill the buffer with data
    ///
    /// - Parameter data: data to be stored in the buffer
    ///
    /// - Returns: ???
    ///
    func readHelper(into data: NSMutableData) -> Int {

        let length = responseBuffers.fill(data: data)
        return  length > 0 ? length : -1
    }
    
}
