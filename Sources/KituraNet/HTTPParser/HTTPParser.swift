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
import CHTTPParser
import Foundation

// MARK: HTTPParser

class HTTPParser {

    ///
    /// A Handle to the HTTPParser C-library
    ///
    var parser: http_parser

    ///
    /// Settings used for HTTPParser
    ///
    var settings: http_parser_settings

    ///
    /// Parsing a request? (or a response)
    ///
    var isRequest = true

    ///
    /// Delegate used for the parsing
    ///
    var delegate: HTTPParserDelegate? {

        didSet {
            if let _ = delegate {
                withUnsafeMutablePointer(&delegate) {
                    ptr in
                    self.parser.data = UnsafeMutablePointer<Void>(ptr)
                }
            }
        }
        
    }
    
    ///
    /// Whether to upgrade the HTTP connection to HTTP 1.1
    ///
    var upgrade = 1

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
        settings = http_parser_settings()

        settings.on_url = { (parser, chunk, length) -> Int32 in
            let p = UnsafePointer<HTTPParserDelegate?>(parser?.pointee.data)
            let data = NSData(bytes: chunk, length: length)
            p?.pointee?.onURL(data)
            return 0
        }
        
        settings.on_header_field = { (parser, chunk, length) -> Int32 in
            let data = NSData(bytes: chunk, length: length)
            let p = UnsafePointer<HTTPParserDelegate?>(parser?.pointee.data)
            p?.pointee?.onHeaderField(data)
            return 0
        }
        
        settings.on_header_value = { (parser, chunk, length) -> Int32 in
            let data = NSData(bytes: chunk, length: length)
            let p = UnsafePointer<HTTPParserDelegate?>(parser?.pointee.data)
            p?.pointee?.onHeaderValue(data)
            return 0
        }
        
        settings.on_body = { (parser, chunk, length) -> Int32 in
            let p = UnsafePointer<HTTPParserDelegate?>(parser?.pointee.data)
            if p?.pointee?.saveBody == true {
                let data = NSData(bytes: chunk, length: length)
                p?.pointee?.onBody(data)
            }
            return 0
        }
        
        settings.on_headers_complete = { (parser) -> Int32 in
            let p = UnsafePointer<HTTPParserDelegate?>(parser?.pointee.data)
            // TODO: Clean and refactor
            //let method = String( get_method(parser))
            let po =  get_method(parser)
            var message = ""
            var i = 0
            while((po!+i).pointee != Int8(0)) {
                message += String(UnicodeScalar(UInt8((po!+i).pointee)))
                i += 1
            }
            p?.pointee?.onHeadersComplete(method: message, versionMajor: (parser?.pointee.http_major)!,
                versionMinor: (parser?.pointee.http_minor)!)
            
            return 0
        }
        
        settings.on_message_begin = { (parser) -> Int32 in
            let p = UnsafePointer<HTTPParserDelegate?>(parser?.pointee.data)
            p?.pointee?.onMessageBegin()
            
            return 0
        }
        
        settings.on_message_complete = { (parser) -> Int32 in
            let p = UnsafePointer<HTTPParserDelegate?>(parser?.pointee.data)
            if get_status_code(parser) == 100 {
                p?.pointee?.prepareToReset()
            }
            else {
                p?.pointee?.onMessageComplete()
            }
            
            return 0
        }
        
        reset()	
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
        let nparsed = http_parser_execute(&parser, &settings, data, length)
        let upgrade = get_upgrade_value(&parser)
        return (nparsed, upgrade)
    }    

    ///
    /// Reset the http_parser context structure.
    ///
    func reset() {
        http_parser_init(&parser, isRequest ? HTTP_REQUEST : HTTP_RESPONSE)
    }

    ///
    /// Did the request include a Connection: keep-alive header?
    ///
    func isKeepAlive() -> Bool {
        return isRequest && http_should_keep_alive(&parser) == 1
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
    func prepareToReset()    
}
