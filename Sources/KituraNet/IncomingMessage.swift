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
import Socket

import Foundation

// MARK: IncomingMessage

public class IncomingMessage : HTTPParserDelegate, SocketReader {

    ///
    /// Default buffer size used for creating a BufferList
    ///
    private static let bufferSize = 2000

    /// 
    /// Major version for HTTP 
    ///
    public private(set) var httpVersionMajor: UInt16?

    ///
    /// Minor version for HTTP
    ///
    public private(set) var httpVersionMinor: UInt16?

    ///
    /// Set of headers
    ///
    public var headers = HeadersContainer()

    ///
    /// HTTP Method
    ///
    public private(set) var method: String = "" // TODO: enum?

    ///
    /// URL
    ///
    public private(set) var urlString = ""

    ///
    /// Raw URL
    ///
    public private(set) var url = NSMutableData()

    // MARK: - Private
    
    // TODO: trailers

    ///
    /// TODO: ???
    ///
    private var lastHeaderWasAValue = false

    ///
    /// TODO: ???
    ///
    private var lastHeaderField = NSMutableData()

    ///
    /// TODO: ???
    ///
    private var lastHeaderValue = NSMutableData()

    ///
    /// TODO: ???
    ///
    private var httpParser: HTTPParser?

    ///
    /// TODO: ???
    ///
    private var status = Status.initial

    ///
    /// Chunk of body read in by the http_parser, filled by callbacks to onBody
    ///
    private var bodyChunk = BufferList()

    ///
    /// TODO: ???
    ///
    private weak var helper: IncomingMessageHelper?

    ///
    /// TODO: ???
    ///
    private var ioBuffer = NSMutableData(capacity: IncomingMessage.bufferSize)
    
    ///
    /// TODO: ???
    ///
    private var buffer = NSMutableData(capacity: IncomingMessage.bufferSize)

    ///
    /// Indicates if the parser should save the message body and call onBody()
    ///
    var saveBody = true
    
    ///
    /// List of status states
    ///
    private enum Status {
        
        case initial
        case headersComplete
        case messageComplete
        case error
        case reset
        
    }


    ///
    /// HTTP parser error types
    ///
    public enum HTTPParserErrorType {
        
        case success
        case parsedLessThanRead
        case unexpectedEOF
        case internalError // TODO
        
    }

    ///
    /// Initializes a new IncomingMessage
    ///
    /// - Parameter isRequest: whether this message is a request
    ///
    /// - Returns: an IncomingMessage instance
    ///
    init (isRequest: Bool) {
        httpParser = HTTPParser(isRequest: isRequest)

        httpParser!.delegate = self
    }

    ///
    /// Sets a helper delegate
    ///
    /// - Parameter helper: the IncomingMessageHelper
    ///
    func setup(_ helper: IncomingMessageHelper) {
        self.helper = helper
    }


    ///
    /// Parse the message
    ///
    /// - Parameter callback: (HTTPParserErrorType) -> Void closure
    ///
    func parse (_ callback: (HTTPParserErrorType) -> Void) {
        guard let parser = httpParser where status == .initial else {
            freeHTTPParser()
            callback(.internalError)
            return
        }

        var start = 0
        var length = 0
        while status == .initial {
            do {
                if  start == 0  {
                    ioBuffer!.length = 0
                    length = try helper!.readHelper(into: ioBuffer!)
                }
                if length > 0 {
                    let offset = start
                    start = 0
                    let (nparsed, upgrade) = parser.execute(UnsafePointer<Int8>(ioBuffer!.bytes)+offset, length: length)
                    if upgrade == 1 {
                        // TODO handle new protocol
                    }
                    else if (nparsed != length) {

                        if  status == .reset  {
                            // Apparently the short message was a Continue. Let's just keep on parsing
                            status = .initial
                            start = nparsed
                            length -= nparsed
                            parser.reset()
                        }
                        else {
                            /* Handle error. Usually just close the connection. */
                            freeHTTPParser()
                            status = .error
                            callback(.parsedLessThanRead)
                        }
                    }
                }
                else {
                    /* Handle unexpected EOF. Usually just close the connection. */
                    freeHTTPParser()
                    status = .error
                    callback(.unexpectedEOF)
                }
            }
            catch {
                /* Handle error. Usually just close the connection. */
                freeHTTPParser()
                status = .error
                callback(.unexpectedEOF)
            }
        }
        if status != .error {
            callback(.success)
        }
    }

    ///
    /// Read data in the message
    ///
    /// - Parameter data: An NSMutableData to hold the data in the message
    ///
    /// - Returns: the number of bytes read
    ///
    public func read(into data: NSMutableData) throws -> Int {
        var count = bodyChunk.fill(data: data)
        if count == 0 {
            if let parser = httpParser where status == .headersComplete {
                do {
                    ioBuffer!.length = 0
                    count = try helper!.readHelper(into: ioBuffer!)
                    if count > 0 {
                        let (nparsed, upgrade) = parser.execute(UnsafePointer<Int8>(ioBuffer!.bytes), length: count)
                        if upgrade == 1 {
                            // TODO: handle new protocol
                        }
                        else if (nparsed != count) {
                            /* Handle error. Usually just close the connection. */
                            freeHTTPParser()
                            status = .error
                        }
                        else {
                            count = bodyChunk.fill(data: data)
                        }
                    }
                    else {
                        status = .messageComplete
                        freeHTTPParser()
                    }
                }
                catch let error {
                    /* Handle error. Usually just close the connection. */
                    freeHTTPParser()
                    status = .error
                    throw error
                }
            }
        }

        return count
    }

    ///
    /// Read all data in the message
    ///
    /// - Parameter data: An NSMutableData to hold the data in the message
    ///
    /// - Returns: the number of bytes read
    ///
    public func readAllData(into data: NSMutableData) throws -> Int {
        var length = try read(into: data)
        var bytesRead = length
        while length != 0 {
            length = try read(into: data)
            bytesRead += length
        }
        return bytesRead
    }

    
    ///
    /// Read message body without storing it anywhere
    ///
    func drain() {
        if let parser = httpParser {
            saveBody = false
            while status == .headersComplete {
                do {
                    ioBuffer!.length = 0
                    let count = try helper!.readHelper(into: ioBuffer!)
                    if count > 0 {
                        let (nparsed, _) = parser.execute(UnsafePointer<Int8>(ioBuffer!.bytes), length: count)
                        if (nparsed != count) {
                            freeHTTPParser()
                            status = .error
                        }
                    }
                    else {
                        status = .messageComplete
                        freeHTTPParser()
                    }
                }
                catch {
                    freeHTTPParser()
                    status = .error
                }
            }
        }
    }

    ///
    /// Read the string
    ///
    /// - Throws: TODO ???
    /// - Returns: an Optional string
    ///
    public func readString() throws -> String? {

        buffer!.length = 0
        let length = try read(into: buffer!)
        if length > 0 {
            return StringUtils.fromUtf8String(buffer!)
        }
        else {
            return nil
        }
        
    }

    ///
    /// Free the httpParser from the IncomingMessage
    ///
    private func freeHTTPParser () {
        
        httpParser?.delegate = nil
        httpParser = nil
        
    }


    ///
    /// Instructions for when reading URL portion
    ///
    /// - Parameter data: the data
    ///
    func onUrl(_ data: NSData) {

        url.append(data)
    }


    ///
    /// Instructions for when reading header field
    ///
    /// - Parameter data: the data
    ///
    func onHeaderField (_ data: NSData) {
        
        if lastHeaderWasAValue {
            addHeader()
        }
        lastHeaderField.append(data)
        lastHeaderWasAValue = false
        
    }

    ///
    /// Instructions for when reading a header value
    ///
    /// - Parameter data: the data
    ///
    func onHeaderValue (_ data: NSData) {

        lastHeaderValue.append(data)
        lastHeaderWasAValue = true

    }

    ///
    /// Set the header key-value pair
    ///
    private func addHeader() {

        let headerKey = StringUtils.fromUtf8String(lastHeaderField)!
        let headerValue = StringUtils.fromUtf8String(lastHeaderValue)!
        
        switch(headerKey.lowercased()) {
            // Headers with a simple value that are not merged (i.e. duplicates dropped)
            // https://mxr.mozilla.org/mozilla/source/netwerk/protocol/http/src/nsHttpHeaderArray.cpp
            //
            case "content-type", "content-length", "user-agent", "referer", "host",
                 "authorization", "proxy-authorization", "if-modified-since",
                 "if-unmodified-since", "from", "location", "max-forwards",
                 "retry-after", "etag", "last-modified", "server", "age", "expires":
                if let _ = headers[headerKey] {
                    break
                }
                fallthrough
            default:
                headers.append(headerKey, value: headerValue)
        }

        lastHeaderField.length = 0
        lastHeaderValue.length = 0

    }

    ///
    /// Instructions for when reading the body of the message
    ///
    /// - Parameter data: the data
    ///
    func onBody (_ data: NSData) {

        self.bodyChunk.append(data: data)

    }

    ///
    /// Instructions for when the headers have been finished being parsed.
    ///
    /// - Parameter method: the HTTP method
    /// - Parameter versionMajor: major version of HTTP
    /// - Parameter versionMinor: minor version of HTTP 
    ///
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16) {
        
        httpVersionMajor = versionMajor
        httpVersionMinor = versionMinor
        self.method = method
        urlString = StringUtils.fromUtf8String(url) ?? ""

        if  lastHeaderWasAValue  {
            addHeader()
        }

        status = .headersComplete
        
    }


    ///
    /// Instructions for when beginning to read a message 
    ///
    func onMessageBegin() {
    }


    ///
    /// Instructions for when done reading the message 
    ///
    func onMessageComplete() {
        
        status = .messageComplete
        freeHTTPParser()
        
    }

    ///
    /// instructions for when reading is reset
    ///
    func reset() {
        lastHeaderWasAValue = false
        url.length = 0
        status = .reset
    }

}

///
/// Protocol for IncomingMessageHelper
protocol IncomingMessageHelper: class {

    ///
    /// TODO: ???
    ///
    func readHelper(into data: NSMutableData) throws -> Int

}
