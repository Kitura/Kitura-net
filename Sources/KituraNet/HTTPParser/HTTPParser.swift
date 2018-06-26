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

    /// HTTP Method of the incoming message.
    var method: String { return parseResults.method }
    
    /// The path specified in an incoming message
    var url: NSData { return parseResults.url }
    
    /// The path specified in an incoming message as a String
    var urlString: String { return parseResults.urlString }
    
    /// Major version of HTTP of the request
    var httpVersionMajor: UInt16 { return parseResults.httpVersionMajor }
    
    /// Minor version of HTTP of the request
    var httpVersionMinor: UInt16 { return parseResults.httpVersionMinor }
    
    /// Set of HTTP headers of the incoming message.
    var headers: HeadersContainer { return parseResults.headers }
    
    /// Chunk of body read in by the http_parser
    var bodyChunk: BufferList { return parseResults.bodyChunk }
    
    /// Parsing of message completed
    var completed: Bool { return parseResults.completed }
    
    /// A Handle to the HTTPParser C-library
    var parser: http_parser

    /// Settings used for HTTPParser
    var settings: http_parser_settings

    /// Parsing a request? (or a response)
    var isRequest = true
    
    /// Results of the parsing of an HTTP incoming message
    private var parseResults = ParseResults()
    
    /// Whether to upgrade the HTTP connection to HTTP 1.1
    var upgrade = 1

    /// Initializes a HTTPParser instance
    ///
    /// - Parameter isRequest: whether or not this HTTP message is a request
    /// - Parameter skipBody: whether parser should skip body content (ie when parsing the response to a HEAD request)
    ///
    /// - Returns: an HTTPParser instance
    init(isRequest: Bool, skipBody: Bool = false) {

        self.isRequest = isRequest

        parser = http_parser()
        settings = http_parser_settings()
        
        parser.data = UnsafeMutableRawPointer(&parseResults)
        
        settings.on_url = { (parser, chunk, length) -> Int32 in
            let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
            getResults(parser)?.onURL(ptr, count: length)
            return 0
        }
        
        settings.on_header_field = { (parser, chunk, length) -> Int32 in
            let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
            getResults(parser)?.onHeaderField(ptr, count: length)
            return 0
        }
        
        settings.on_header_value = { (parser, chunk, length) -> Int32 in
            let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
            getResults(parser)?.onHeaderValue(ptr, count: length)
            return 0
        }
        
        settings.on_body = { (parser, chunk, length) -> Int32 in
            let delegate = getResults(parser)
            let ptr = UnsafeRawPointer(chunk!).assumingMemoryBound(to: UInt8.self)
            delegate?.onBody(ptr, count: length)
            return 0
        }
        
        // Callback should return 1 when instructing the C HTTP parser
        // to skip body content. This closure is bound to a C function
        // pointer and cannot capture values (including self.skipBody)
        // so instead we choose which closure to assign outside the
        // closure.
        if skipBody {
            settings.on_headers_complete = { (parser) -> Int32 in
                onHeadersComplete(parser)
                return 1
            }
        } else {
            settings.on_headers_complete = { (parser) -> Int32 in
                onHeadersComplete(parser)
                return 0
            }
        }
        
        // When the parser reaches the end of a message, we will pause
        // so that execute() completes and the handler can be invoked.
        // Any remaining data in the buffer will be consumed as follows:
        // - if Keep-Alive is disabled, the data will be discarded.
        // - if Keep-Alive is enabled, the keepAlive() call and the
        //   subsequent handleBuffererdReadData() call will reset the
        //   parser's state, and then resume parsing the buffer.
        settings.on_message_complete = { (parser) -> Int32 in
            getResults(parser)?.onMessageComplete()
            http_parser_pause(parser, 1)
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
        parseResults.reset()
    }

    /// Did the request include a Connection: keep-alive header?
    func isKeepAlive() -> Bool {
        return isRequest && http_should_keep_alive(&parser) == 1
    }

    /// Get the HTTP status code on responses
    var statusCode: HTTPStatusCode {
        return isRequest ? .unknown : HTTPStatusCode(rawValue: Int(parser.status_code)) ?? .unknown
    }
}

fileprivate func onHeadersComplete(_ parser: UnsafeMutableRawPointer?) {
    let httpParser = parser?.assumingMemoryBound(to: http_parser.self)
    let method = String(cString: get_method(httpParser!))

    let results = getResults(httpParser)

    results?.onHeadersComplete(method: method, versionMajor: (httpParser?.pointee.http_major)!,
        versionMinor: (httpParser?.pointee.http_minor)!)
}

fileprivate func getResults(_ parser: UnsafeMutableRawPointer?) -> ParseResults? {
    let httpParser = parser?.assumingMemoryBound(to: http_parser.self)
    let httpParserData = httpParser?.pointee.data
    return httpParserData?.assumingMemoryBound(to: ParseResults.self).pointee
}
