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

/// The ServerResponse protocol allows responses to be abstracted
/// across different networking protocols in an agnostic way to the
/// Kitura project Router.
public protocol ServerResponse: class {
    
    /// The status code to send in the HTTP response.
    var statusCode: HTTPStatusCode? { get set }
    
    /// The headers to send back as part of the HTTP response.
    var headers : HeadersContainer { get }
    
    /// Add a string to the body of the HTTP response.
    ///
    /// - Parameter string: The String data to be added.
    ///
    /// - Throws: Socket.error if an error occurred while writing to the socket
    func write(from string: String) throws
    
    /// Add bytes to the body of the HTTP response.
    ///
    /// - Parameter data: The Data struct that contains the bytes to be added.
    ///
    /// - Throws: Socket.error if an error occurred while writing to the socket
    func write(from data: Data) throws
    
    /// Add a string to the body of the HTTP response and complete sending the HTTP response
    ///
    /// - Parameter text: The String to add to the body of the HTTP response.
    ///
    /// - Throws: Socket.error if an error occurred while writing to the socket
    func end(text: String) throws
    
    /// Complete sending the HTTP response
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    func end() throws
    
    /// Reset this response object back to it's initial state
    func reset()
    
}
