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

/// class to hold results of callbacks from the http_parser
class ParseResults {
    /// Have the parsing completed? (MessageComplete)
    var completed = false
    
    /// HTTP Method of the incoming message.
    private(set) var method = ""
    
    /// URL path and query string from request
    let url = NSMutableData(capacity: 2000) ?? NSMutableData()
    
    /// URL path and query string from request in String form
    var urlString = ""
    
    /// Major version for HTTP of the incoming message.
    private(set) var httpVersionMajor: UInt16 = 0
    
    /// Minor version for HTTP of the incoming message.
    private(set) var httpVersionMinor: UInt16 = 0
    
    /// Set of HTTP headers of the incoming message.
    var headers = HeadersContainer()
    
    /// State of callbacks from parser WRT headers
    private var lastHeaderWasAValue = false
    
    /// Bytes of a header key that was just parsed and returned in chunks by the pars
    private let lastHeaderField = NSMutableData()
    
    /// Bytes of a header value that was just parsed and returned in chunks by the parser
    private let lastHeaderValue = NSMutableData()
    
    /// Chunk of body read in by the http_parser, filled by callbacks to onBody
    private(set) var bodyChunk = BufferList()
    
    init() {}
    
    /// Callback for when a piece of the body of the message was parsed
    ///
    /// - Parameter bytes: The bytes of the parsed body
    /// - Parameter count: The number of bytes parsed
    func onBody (_ bytes: UnsafePointer<UInt8>, count: Int) {
        bodyChunk.append(bytes: bytes, length: count)
    }
    
    /// Callback for when the headers have been finished being parsed.
    ///
    /// - Parameter method: the HTTP method
    /// - Parameter versionMajor: major version of HTTP
    /// - Parameter versionMinor: minor version of HTTP
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16) {
        httpVersionMajor = versionMajor
        httpVersionMinor = versionMinor
        self.method = method
        if  lastHeaderWasAValue  {
            addHeader()
        }
        
        var zero: CChar = 0
        url.append(&zero, length: 1)
        urlString = String(cString: url.bytes.assumingMemoryBound(to: CChar.self))
        url.length -= 1
    }
    
    /// Callback for when a piece of a header key was parsed
    ///
    /// - Parameter bytes: The bytes of the parsed header key
    /// - Parameter count: The number of bytes parsed
    func onHeaderField (_ bytes: UnsafePointer<UInt8>, count: Int) {
        
        if lastHeaderWasAValue {
            addHeader()
        }
        lastHeaderField.append(bytes, length: count)
        
        lastHeaderWasAValue = false
        
    }
    
    /// Callback for when a piece of a header value was parsed
    ///
    /// - Parameter bytes: The bytes of the parsed header value
    /// - Parameter count: The number of bytes parsed
    func onHeaderValue (_ bytes: UnsafePointer<UInt8>, count: Int) {
        lastHeaderValue.append(bytes, length: count)
        
        lastHeaderWasAValue = true
    }
    
    /// Callback for when the HTTP message is completely parsed
    func onMessageComplete() {
        completed = true
    }
    
    /// Instructions for when reading URL portion
    ///
    /// - Parameter bytes: The bytes of the parsed URL
    /// - Parameter count: The number of bytes parsed
    func onURL(_ bytes: UnsafePointer<UInt8>, count: Int) {
        url.append(bytes, length: count)
    }
    
    func reset() {
        completed = false
        lastHeaderWasAValue = false
        bodyChunk.reset()
        headers.removeAll()
        url.length = 0
    }
    
    /// Set the header key-value pair
    private func addHeader() {
        var zero: CChar = 0
        lastHeaderField.append(&zero, length: 1)
        let headerKey = String(cString: lastHeaderField.bytes.assumingMemoryBound(to: CChar.self))
        lastHeaderValue.append(&zero, length: 1)
        let headerValue = String(cString: lastHeaderValue.bytes.assumingMemoryBound(to: CChar.self))
        
        headers.append(headerKey, value: headerValue)
        
        lastHeaderField.length = 0
        lastHeaderValue.length = 0
        
    }
}
