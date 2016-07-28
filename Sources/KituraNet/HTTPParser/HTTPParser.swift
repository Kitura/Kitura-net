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

import KituraSys
import HTTPParser
import Foundation

// MARK: HTTPParser

class HTTPParser : http_parser_delegate {

    ///
    /// A Handle to the HTTPParser C-library
    ///
    var parser: http_parser

    ///
    /// Parsing a request? (or a response)
    ///
    var isRequest = true

    ///
    /// Delegate used for the parsing
    ///
    var delegate: HTTPParserDelegate?
    
    ///
    /// Initializes a HTTPParser instance
    ///
    /// - Parameter isRequest: whether or not this HTTP message is a request
    ///
    /// - Returns: an HTTPParser instance
    ///
    init(isRequest: Bool) {

        self.isRequest = isRequest

        parser = http_parser()
        
        reset()
    }

    ///
    /// http_parser_delegate eethods
    ///
    func on_url(at: UnsafePointer<UInt8>, length: Int) -> Int{
        let data = NSData(bytes: at, length: length)
        delegate?.onURL(data)
        return 0
    }

    func on_header_field(at: UnsafePointer<UInt8>, length: Int) -> Int {
        let data = NSData(bytes: at, length: length)
        delegate?.onHeaderField(data)
        return 0
    }

    func on_header_value(at: UnsafePointer<UInt8>, length: Int) -> Int {
        let data = NSData(bytes: at, length: length)
        delegate?.onHeaderValue(data)
        return 0
    }

    func on_body(at: UnsafePointer<UInt8>, length: Int) -> Int {
        if delegate?.saveBody == true {
            let data = NSData(bytes: at, length: length)
            delegate?.onBody(data)
        }
        return 0
    }

    func on_headers_complete() -> Int {
        let message = parser.method_str(parser.method)
        delegate?.onHeadersComplete(method: message, versionMajor: parser.http_major,
            versionMinor: parser.http_minor)
        return 0
    }

    func on_message_begin() -> Int {
        delegate?.onMessageBegin()
        return 0
    }

    func on_message_complete() -> Int {
        if parser.status_code == 100 {
            delegate?.reset()
        }
        else {
            delegate?.onMessageComplete()
        }
        return 0
    }

    ///
    /// unused HTTPParser callbacks
    ///
    func on_status(at: UnsafePointer<UInt8>, length: Int) -> Int {
        return 0
    }

    func on_chunk_header() -> Int {
        return 0
    }

    func on_chunk_complete() -> Int {
        return 0
    }

    ///
    /// Executes the parsing on the byte array
    ///
    /// - Parameter data: pointer to a byte array
    /// - Parameter length: length of the byte array
    ///
    /// - Returns: ???
    ///
    func execute (_ data: UnsafePointer<Int8>, length: Int) -> (Int, UInt32) {
        let nparsed = parser.execute(self, UnsafePointer<UInt8>(data), length)
        return (nparsed, parser.upgrade ? 1 : 0)
    }    

    ///
    /// Reset the http_parser context structure.
    ///
    func reset() {
        parser.reset(isRequest ? .HTTP_REQUEST : .HTTP_RESPONSE)
    }

    ///
    /// Did the request include a Connection: keep-alive header?
    ///
    func isKeepAlive() -> Bool {
        return isRequest && parser.should_keep_alive()
    }

}

///
/// Delegate protocol for HTTP parsing stages
///
protocol HTTPParserDelegate: class {
    var saveBody : Bool { get }
    func onURL(_ url:NSData)
    func onHeaderField(_ data: NSData)
    func onHeaderValue(_ data: NSData)
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16)
    func onMessageBegin()
    func onMessageComplete()
    func onBody(_ body: NSData)
    func reset()    
}
