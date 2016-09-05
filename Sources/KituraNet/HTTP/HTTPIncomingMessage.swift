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


import KituraSys
import Socket

import Foundation

// MARK: IncomingMessage

/// A representation of HTTP incoming message.
public class HTTPIncomingMessage : HTTPParserDelegate {

    /// Major version for HTTP of the incoming message.
    public private(set) var httpVersionMajor: UInt16?

    /// Minor version for HTTP of the incoming message.
    public private(set) var httpVersionMinor: UInt16?

    /// Set of HTTP headers of the incoming message.
    public var headers = HeadersContainer()

    /// HTTP Method of the incoming message.
    public private(set) var method: String = "" 

    /// URL of the incoming message.
    public private(set) var urlString = ""

    /// Raw URL of the incoming message.
    public private(set) var url = Data()

    /// Indicates if the parser should save the message body and call onBody()
    var saveBody = true

    // Private
    
    /// Default buffer size used for creating a BufferList
    private static let bufferSize = 2000

    /// State of callbacks from parser WRT headers
    private var lastHeaderWasAValue = false

    /// Bytes of a header key that was just parsed and returned in chunks by the pars
    private var lastHeaderField = Data()

    /// Bytes of a header value that was just parsed and returned in chunks by the parser
    private var lastHeaderValue = Data()

    /// The http_parser Swift wrapper
    private var httpParser: HTTPParser?

    /// State of incoming message handling
    private var status = HTTPParserStatus()

    /// Chunk of body read in by the http_parser, filled by callbacks to onBody
    private var bodyChunk = BufferList()

    /// Reader helper, reads from underlying data source
    private weak var helper: IncomingMessageHelper?

    private var ioBuffer = Data(capacity: HTTPIncomingMessage.bufferSize)
    
    private var buffer = Data(capacity: HTTPIncomingMessage.bufferSize)
    
    
    /// Initializes a new IncomingMessage
    ///
    /// - Parameter isRequest: whether this message is a request
    ///
    /// - Returns: an IncomingMessage instance
    init (isRequest: Bool) {
        httpParser = HTTPParser(isRequest: isRequest)

        httpParser!.delegate = self
    }

    /// Sets a helper delegate
    ///
    /// - Parameter helper: the IncomingMessageHelper
    func setup(_ helper: IncomingMessageHelper) {
        self.helper = helper
    }
    
    /// Parse the message
    ///
    /// - Parameter callback: (HTTPParserStatus) -> Void closure
    func parse (_ buffer: Data) -> HTTPParserStatus {
        guard let parser = httpParser else {
            status.error = .internalError
            return status
        }
        
        var length = buffer.count
        
        guard length > 0  else {
            /* Handle unexpected EOF. Usually just close the connection. */
            freeHTTPParser()
            status.error = .unexpectedEOF
            return status
        }
        
        // If we were reset because of keep alive
        if  status.state == .reset  {
            reset()
        }
        
        var start = 0
        while status.state == .initial  &&  status.error == nil  &&  length > 0  {
            
            buffer.withUnsafeBytes() { [unowned self] (bytes: UnsafePointer<Int8>) in
                let (numberParsed, upgrade) = parser.execute(bytes+start, length: length)
                if upgrade == 1 {
                    // TODO handle new protocol
                }
                else if  numberParsed != length  {
                
                    if  self.status.state == .reset  {
                        // Apparently the short message was a Continue. Let's just keep on parsing
                        start = numberParsed
                        self.reset()
                    }
                    else {
                        /* Handle error. Usually just close the connection. */
                        self.freeHTTPParser()
                        self.status.error = .parsedLessThanRead
                    }
                }
                length -= numberParsed
            }
        }
        
        return status
    }

    /// Read a chunk of the body of the message.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the message.
    /// - Throws: if an error occurs while reading the body.
    /// - Returns: the number of bytes read.
    public func read(into data: inout Data) throws -> Int {
        var count = bodyChunk.fill(data: &data)
        if count == 0 {
            if let parser = httpParser, status.state == .headersComplete {
                do {
                    ioBuffer.count = 0
                    count = try helper!.readHelper(into: &ioBuffer)
                    if count > 0 {
                        let (numberParsed, upgrade) =
                                ioBuffer.withUnsafeBytes() { (bytes: UnsafePointer<Int8>) -> (Int, UInt32) in
                            return parser.execute(bytes, length: count)
                        }
                        if upgrade == 1 {
                            // TODO: handle new protocol
                        }
                        else if (numberParsed != count) {
                            /* Handle error. Usually just close the connection. */
                            self.freeHTTPParser()
                            self.status.error = .parsedLessThanRead
                        }
                        else {
                            count = self.bodyChunk.fill(data: &data)
                        }
                    }
                    else {
                        onMessageComplete()
                    }
                }
                catch let error {
                    /* Handle error. Usually just close the connection. */
                    freeHTTPParser()
                    status.error = .internalError
                    throw error
                }
            }
        }

        return count
    }

    /// Read the whole body of the message.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the message.
    /// - Throws: if an error occurs while reading the data.
    /// - Returns: the number of bytes read.
    @discardableResult
    public func readAllData(into data: inout Data) throws -> Int {
        var length = try read(into: &data)
        var bytesRead = length
        while length > 0 {
            length = try read(into: &data)
            bytesRead += length
        }
        return bytesRead
    }

    /// Read message body without storing it anywhere
    func drain() {
        if let parser = httpParser {
            saveBody = false
            while status.state == .headersComplete {
                do {
                    ioBuffer.count = 0
                    let count = try helper!.readHelper(into: &ioBuffer)
                    if count > 0 {
                        ioBuffer.withUnsafeBytes() { [unowned self] (bytes: UnsafePointer<Int8>) in
                            let (numberParsed, _) = parser.execute(bytes, length: count)
                            if (numberParsed != count) {
                                self.freeHTTPParser()
                                self.status.error = .parsedLessThanRead
                            }
                        }
                    }
                    else {
                        onMessageComplete()
                    }
                }
                catch {
                    freeHTTPParser()
                    status.error = .internalError
                }
            }
        }
    }

    /// Read a chunk of the body and return it as a String.
    ///
    /// - Throws: if an error occurs while reading the data.
    /// - Returns: an Optional string.
    public func readString() throws -> String? {
        buffer.count = 0
        let length = try read(into: &buffer)
        if length > 0 {
            return StringUtils.fromUtf8String(buffer)
        }
        else {
            return nil
        }
    }

    /// Free the httpParser from the IncomingMessage
    private func freeHTTPParser () {
        httpParser?.delegate = nil
        httpParser = nil
    }

    /// Instructions for when reading URL portion
    ///
    /// - Parameter data: the data
    func onURL(_ data: Data) {
        url.append(data)
    }

    /// Instructions for when reading header field
    ///
    /// - Parameter data: the data
    func onHeaderField (_ data: Data) {
        
        if lastHeaderWasAValue {
            addHeader()
        }
        lastHeaderField.append(data)

        lastHeaderWasAValue = false
        
    }

    /// Instructions for when reading a header value
    ///
    /// - Parameter data: the data
    func onHeaderValue (_ data: Data) {
        lastHeaderValue.append(data)

        lastHeaderWasAValue = true
    }

    /// Set the header key-value pair
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

        lastHeaderField.count = 0
        lastHeaderValue.count = 0

    }

    /// Instructions for when reading the body of the message
    ///
    /// - Parameter data: the data
    func onBody (_ data: Data) {
        self.bodyChunk.append(data: data)

    }

    /// Instructions for when the headers have been finished being parsed.
    ///
    /// - Parameter method: the HTTP method
    /// - Parameter versionMajor: major version of HTTP
    /// - Parameter versionMinor: minor version of HTTP
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16) {
        
        httpVersionMajor = versionMajor
        httpVersionMinor = versionMinor
        self.method = method
        urlString = StringUtils.fromUtf8String(url) ?? ""

        if  lastHeaderWasAValue  {
            addHeader()
        }

        status.keepAlive = httpParser?.isKeepAlive() ?? false
        status.state = .headersComplete
        
    }

    /// Instructions for when beginning to read a message
    func onMessageBegin() {
    }

    /// Instructions for when done reading the message
    func onMessageComplete() {
        
        status.keepAlive = httpParser?.isKeepAlive() ?? false
        status.state = .messageComplete
        if  !status.keepAlive  {
            freeHTTPParser()
        }
    }
    
    /// Signal that the connection is being closed, and resources should be freed
    func close() {
        freeHTTPParser()
    }

    /// Signal that reading is being reset
    func prepareToReset() {
        status.state = .reset
    }

    /// When we're ready, really reset everything
    private func reset() {
        lastHeaderWasAValue = false
        saveBody = true
        url.count = 0
        headers.removeAll()
        bodyChunk.reset()
        status.reset()
        httpParser?.reset()
    }
}


/// Protocol for IncomingMessageHelper
protocol IncomingMessageHelper: class {

    /// "Read" data from the actual underlying transport
    ///
    /// - Parameter into: The NSMutableData that will be receiving the data read in.
    /// - Throws: if an error occurs while reading the data
    func readHelper(into data: inout Data) throws -> Int

}
