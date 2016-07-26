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

// This is a ServerRequest protocol class that allows requests
// to be abstracted across different protocols in an agnostic way to the 
// Kitura project Router.
public protocol ServerRequest: class {
    
    /// Set of headers
    var headers : HeadersContainer { get set }
    
    /// URL
    var urlString : String { get }
    
    /// Raw URL
    var url : NSMutableData { get }

    /// server IP address
    var remoteAddress: String { get }
    
    /// Major version for HTTP
    var httpVersionMajor: UInt16? { get }

    /// Minor version for HTTP
    var httpVersionMinor: UInt16? { get }
    
    /// HTTP Method
    var method: String { get }
    
    /// Read data in the message
    ///
    /// - Parameter data: An NSMutableData to hold the data in the message
    ///
    /// - Throws: Socket.error if an error occurred while reading from a socket
    /// - Returns: the number of bytes read
    func read(into data: NSMutableData) throws -> Int
    
    /// Read the string
    ///
    /// - Throws: Socket.error if an error occurred while reading from a socket
    /// - Returns: an Optional string
    func readString() throws -> String?
    
    
    /// Read all data in the message
    ///
    /// - Parameter data: An NSMutableData to hold the data in the message
    ///
    /// - Throws: Socket.error if an error occurred while reading from a socket
    /// - Returns: the number of bytes read
    func readAllData(into data: NSMutableData) throws -> Int
}
