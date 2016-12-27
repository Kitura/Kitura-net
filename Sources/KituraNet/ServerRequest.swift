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

/// The ServerRequest protocol allows requests to be abstracted 
/// across different networking protocols in an agnostic way to the
/// Kitura project Router.
public protocol ServerRequest: class {
    
    /// The set of headers received with the incoming request
    var headers : HeadersContainer { get }

    /// The URL from the request in string form
    /// This contains just the path and query parameters starting with '/'
    /// Use 'urlURL' for the full URL
    @available(*, deprecated, message:
        "This contains just the path and query parameters starting with '/'. use 'urlURL' instead")
    var urlString : String { get }

    /// The URL from the request in UTF-8 form
    /// This contains just the path and query parameters starting with '/'
    /// Use 'urlURL' for the full URL
    var url : Data { get }

    /// The URL from the request as URLComponents
    /// URLComponents has a memory leak on linux as of swift 3.0.1. Use 'urlURL' instead
    @available(*, deprecated, message:
        "URLComponents has a memory leak on linux as of swift 3.0.1. use 'urlURL' instead")
    var urlComponents : URLComponents { get }

    /// The URL from the request
    var urlURL : URL { get }

    /// The IP address of the client
    var remoteAddress: String { get }
    
    /// Major version of HTTP of the request
    var httpVersionMajor: UInt16? { get }

    /// Minor version of HTTP of the request
    var httpVersionMinor: UInt16? { get }
    
    /// The HTTP Method specified in the request
    var method: String { get }
    
    /// Read data from the body of the request
    ///
    /// - Parameter data: A Data struct to hold the data read in.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket
    /// - Returns: The number of bytes read
    func read(into data: inout Data) throws -> Int
    
    /// Read a string from the body of the request.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket
    /// - Returns: An Optional string
    func readString() throws -> String?
    
    
    /// Read all of the data in the body of the request
    ///
    /// - Parameter data: A Data struct to hold the data read in.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket
    /// - Returns: The number of bytes read
    func readAllData(into data: inout Data) throws -> Int
}
