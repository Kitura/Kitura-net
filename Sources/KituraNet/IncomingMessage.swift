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

public class IncomingMessage : HttpParserDelegate, SocketReader {

    ///
    /// Default buffer size used for creating a BufferList
    ///
    private static let BUFFER_SIZE = 2000

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
    public private(set) var headers = Headers()

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
    private var httpParser: HttpParser?

    ///
    /// TODO: ???
    ///
    private var status = Status.Initial

    ///
    /// TODO: ???
    ///
    private var bodyChunk = BufferList()

    ///
    /// TODO: ???
    ///
    private weak var helper: IncomingMessageHelper?

    ///
    /// TODO: ???
    ///
    private var ioBuffer = NSMutableData(capacity: BUFFER_SIZE)
    
    ///
    /// TODO: ???
    ///
    private var buffer = NSMutableData(capacity: BUFFER_SIZE)


    ///
    /// List of status states
    ///
    private enum Status {
        
        case Initial
        case HeadersComplete
        case MessageComplete
        case Error
        
    }


    ///
    /// Http parser error types
    ///
    public enum HttpParserErrorType {
        
        case Success
        case ParsedLessThanRead
        case UnexpectedEOF
        case InternalError // TODO
        
    }

    ///
    /// Initializes a new IncomingMessage
    ///
    /// - Parameter isRequest: whether this message is a request
    ///
    /// - Returns: an IncomingMessage instance
    ///
    init (isRequest: Bool) {
        httpParser = HttpParser(isRequest: isRequest)

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
    /// - Parameter callback: (HttpParserErrorType) -> Void closure
    ///
    func parse (_ callback: (HttpParserErrorType) -> Void) {
        guard let parser = httpParser where status == .Initial else {
            freeHttpParser()
            callback(.InternalError)
            return
        }

        while status == .Initial {
            do {
                ioBuffer!.length = 0
                let length = try helper!.readHelper(into: ioBuffer!)
                if length > 0 {
                    let (nparsed, upgrade) = parser.execute(UnsafePointer<Int8>(ioBuffer!.bytes), length: length)
                    if upgrade == 1 {
                        // TODO handle new protocol
                    }
                    else if (nparsed != length) {
                        /* Handle error. Usually just close the connection. */
                        freeHttpParser()
                        status = .Error
                        callback(.ParsedLessThanRead)
                    }
                }
                else {
                    /* Handle unexpected EOF. Usually just close the connection. */
                    freeHttpParser()
                    status = .Error
                    callback(.UnexpectedEOF)
                }
            }
            catch {
                /* Handle error. Usually just close the connection. */
                freeHttpParser()
                status = .Error
                callback(.UnexpectedEOF)
            }
        }
        if status != .Error {
            callback(.Success)
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
            if let parser = httpParser where status == .HeadersComplete {
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
                            freeHttpParser()
                            status = .Error
                        }
                        else {
                            count = bodyChunk.fill(data: data)
                        }
                    }
                    else {
                        status = .MessageComplete
                        freeHttpParser()
                    }
                }
                catch let error {
                    /* Handle error. Usually just close the connection. */
                    freeHttpParser()
                    status = .Error
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
    private func freeHttpParser () {
        
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
                if let _ = headers.get(headerKey) {
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

        status = .HeadersComplete
        
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
        
        status = .MessageComplete
        freeHttpParser()
        
    }

    ///
    /// instructions for when reading is reset
    ///
    func reset() {
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
