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

import CHTTPParser
import Foundation

// MARK: HTTPParser

class HTTPParser {

    /// A Handle to the HTTPParser C-library
    var parser: http_parser

    /// Settings used for HTTPParser
    var settings: http_parser_settings

    /// Parsing a request? (or a response)
    var isRequest = true

    /// Delegate used for the parsing
    var delegate: HTTPParserDelegate?
    
    /// Whether to upgrade the HTTP connection to HTTP 1.1
    var upgrade = 1
    
    ///Raw pointer to hand to the C Parser. Make this an instance variable so we can reclaim it in deinit().
    let ptrToSelf: UnsafeMutablePointer<HTTPParser>

    /// Initializes a HTTPParser instance
    ///
    /// - Parameter isRequest: whether or not this HTTP message is a request
    ///
    /// - Returns: an HTTPParser instance
    init(isRequest: Bool) {

        self.isRequest = isRequest

        parser = http_parser()
        settings = http_parser_settings()
        
        //Encapsulate a reference to the self object for later retrieval
        // see https://github.com/apple/swift-evolution/blob/master/proposals/0107-unsaferawpointer.md
        // search for "Now we can allocate raw memory and obtain a typed pointer through initialization"
        let rawPtr = UnsafeMutableRawPointer.allocate(bytes: MemoryLayout<HTTPParser>.stride,
                                                      alignedTo: MemoryLayout<HTTPParser>.alignment)
        ptrToSelf = rawPtr.bindMemory(to: HTTPParser.self, capacity: 1)
        ptrToSelf.initialize(to: self)
        
        //Stuff that pointer reference into our C parser so we can get at it during callbacks
        self.parser.data = rawPtr
        
        settings.on_url = { (parser, chunk, length) -> Int32 in
            let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
            getDelegate(parser)?.onURL(ptr, count: length)
            return 0
        }
        
        settings.on_header_field = { (parser, chunk, length) -> Int32 in
            let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
            getDelegate(parser)?.onHeaderField(ptr, count: length)
            return 0
        }
        
        settings.on_header_value = { (parser, chunk, length) -> Int32 in
            let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
            getDelegate(parser)?.onHeaderValue(ptr, count: length)
            return 0
        }
        
        settings.on_body = { (parser, chunk, length) -> Int32 in
            let delegate = getDelegate(parser)
            if delegate?.saveBody == true {
                let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
                delegate?.onBody(ptr, count: length)
            }
            return 0
        }
        
        settings.on_headers_complete = { (parser) -> Int32 in
            // TODO: Clean and refactor
            //let method = String( get_method(parser))
            let po =  get_method(parser)
            var message = ""
            var i = 0
            while((po!+i).pointee != Int8(0)) {
                message += String(UnicodeScalar(UInt8((po!+i).pointee)))
                i += 1
            }
            getDelegate(parser)?.onHeadersComplete(method: message, versionMajor: (parser?.pointee.http_major)!,
                versionMinor: (parser?.pointee.http_minor)!)
            
            return 0
        }
        
        settings.on_message_begin = { (parser) -> Int32 in
            getDelegate(parser)?.onMessageBegin()
            
            return 0
        }
        
        settings.on_message_complete = { (parser) -> Int32 in
            let delegate = getDelegate(parser)
            if get_status_code(parser) == 100 {
                delegate?.prepareToReset()
            }
            else {
                delegate?.onMessageComplete()
            }
            
            return 0
        }
        
        reset()	
    }
    
    /// Executes the parsing on the byte array
    ///
    /// - Parameter data: pointer to a byte array
    /// - Parameter length: length of the byte array
    ///
    /// - Returns: ???
    func execute (_ data: UnsafePointer<Int8>, length: Int) -> (Int, UInt32) {
        let nparsed = http_parser_execute(&parser, &settings, data, length)
        let upgrade = get_upgrade_value(&parser)
        return (nparsed, upgrade)
    }    

    /// Reset the http_parser context structure.
    func reset() {
        http_parser_init(&parser, isRequest ? HTTP_REQUEST : HTTP_RESPONSE)
    }

    /// Did the request include a Connection: keep-alive header?
    func isKeepAlive() -> Bool {
        return isRequest && http_should_keep_alive(&parser) == 1
    }

    /// Get the HTTP status code on responses
    var statusCode: HTTPStatusCode {
        return isRequest ? .unknown : HTTPStatusCode(rawValue: Int(parser.status_code)) ?? .unknown
    }
    
    deinit {
        // Remove the raw pointer memory we allocated in init()
        // see https://github.com/apple/swift-evolution/blob/master/proposals/0107-unsaferawpointer.md
        // search for "Now we can allocate raw memory and obtain a typed pointer through initialization"

        let uninitPtr = ptrToSelf.deinitialize(count: 1)
        uninitPtr.deallocate(bytes: MemoryLayout<HTTPParser>.stride,
                             alignedTo: MemoryLayout<HTTPParser>.alignment)
    }
}

fileprivate func getDelegate(_ parser: UnsafeMutableRawPointer?) -> HTTPParserDelegate? {
    //Note that making these local varables doesn't require any more memory or slow anything down
    //   But (IMNSHO) they make what's going on a lot easier to follow
    let ourParserPointer = parser?.assumingMemoryBound(to: http_parser.self)
    let ourData = ourParserPointer?.pointee.data
    let ourSelf = ourData?.assumingMemoryBound(to: HTTPParser.self).pointee
    let ourDelegate = ourSelf?.delegate
    return ourDelegate
}

/// Delegate protocol for HTTP parsing stages
protocol HTTPParserDelegate: class {
    var saveBody : Bool { get }
    func onURL(_ url: UnsafePointer<UInt8>, count: Int)
    func onHeaderField(_ bytes: UnsafePointer<UInt8>, count: Int)
    func onHeaderValue(_ bytes: UnsafePointer<UInt8>, count: Int)
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16)
    func onMessageBegin()
    func onMessageComplete()
    func onBody(_ bytes: UnsafePointer<UInt8>, count: Int)
    func prepareToReset()    
}
