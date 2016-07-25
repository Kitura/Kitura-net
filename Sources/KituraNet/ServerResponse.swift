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

//
// This is a ServerResponse protocol class that allows responses
// to be abstracted across different protocols in an agnostic way to the
// Kitura project Router.
//

public protocol ServerResponse: class {
    
    /// Status code
    var statusCode: HTTPStatusCode? { get set }
    
    /// Headers being sent back as part of the HTTP response.
    var headers : HeadersContainer { get }
    
    /// Write a string as a response
    ///
    /// - Parameter string: String data to be written.
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    func write(from string: String) throws
    
    /// Write data as a response
    ///
    /// - Parameter data: NSMutableData object to contain read data.
    ///
    /// - Returns: Integer representing the number of bytes read.
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    func write(from data: NSData) throws
    
    /// End the response
    ///
    /// - Parameter text: String to write out socket
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    func end(text: String) throws
    
    /// End sending the response
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    func end() throws
    
    /// Reset this response object back to it's initial state
    func reset()
    
}
