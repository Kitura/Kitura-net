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


import LoggerAPI
import Socket

import Foundation

// MARK: IncomingMessage

/// A representation of HTTP incoming message.
public class HTTPIncomingMessage : HTTPParserDelegate {

    /// Major version for HTTP of the incoming message.
    public private(set) var httpVersionMajor: UInt16?

    /// Minor version for HTTP of the incoming message.
    public private(set) var httpVersionMinor: UInt16?
    
    /// HTTP Status code if this message is a response
    public private(set) var httpStatusCode: HTTPStatusCode = .unknown

    /// Set of HTTP headers of the incoming message.
    public var headers = HeadersContainer()

    /// HTTP Method of the incoming message.
    public private(set) var method: String = "" 
    
    /// socket signature of the request.
    public private(set) var signature: Socket.Signature?
    
    /// The URL from the request if properly received.
    public private(set) var url : URL?

    /// The parsed URL as URLComponents.
    public private(set) var urlComponents = URLComponents()

    /// Parsed path and optional query parameters of the request.
    private var pathAndQueryParams = Data()

    /// Indicates if the parser should save the message body and call onBody()
    var saveBody = true

    // Private
    
    /// Default buffer size used for creating a BufferList
    private static let bufferSize = 2000

    /// State of callbacks from parser WRT headers
    private var lastHeaderWasAValue = false

    /// Bytes of a header key that was just parsed and returned in chunks by the pars
    private let lastHeaderField = NSMutableData()

    /// Bytes of a header value that was just parsed and returned in chunks by the parser
    private let lastHeaderValue = NSMutableData()

    /// The http_parser Swift wrapper
    private var httpParser: HTTPParser?

    /// State of incoming message handling
    private var status = HTTPParserStatus()

    /// Chunk of body read in by the http_parser, filled by callbacks to onBody
    private var bodyChunk = BufferList()

    private var ioBuffer = Data(capacity: HTTPIncomingMessage.bufferSize)
    
    private var buffer = Data(capacity: HTTPIncomingMessage.bufferSize)
    
    
    /// Initializes a new IncomingMessage
    ///
    /// - Parameter isRequest: whether this message is a request
    ///
    /// - Returns: an IncomingMessage instance
    init (isRequest: Bool, signature: Socket.Signature? = nil) {
        self.signature = signature
        httpParser = HTTPParser(isRequest: isRequest)

        httpParser!.delegate = self
    }

    /// Parse the message
    ///
    /// - Parameter buffer: An NSData object contaning the data to be parsed
    func parse (_ buffer: NSData) -> HTTPParserStatus {
        guard let parser = httpParser else {
            status.error = .internalError
            return status
        }
        
        var length = buffer.length
        
        guard length > 0  else {
            /* Handle unexpected EOF. Usually just close the connection. */
            release()
            status.error = .unexpectedEOF
            return status
        }
        
        // If we were reset because of keep alive
        if  status.state == .reset  {
            reset()
        }
        
        var start = 0
        while status.state != .messageComplete  &&  status.error == nil  &&  length > 0  {
            let bytes = buffer.bytes.assumingMemoryBound(to: Int8.self) + start
            let (numberParsed, upgrade) = parser.execute(bytes, length: length)
            if upgrade == 1 {
                status.upgrade = true
            }
            else if  numberParsed != length  {
                
                if  self.status.state == .reset  {
                    // Apparently the short message was a Continue. Let's just keep on parsing
                    start = numberParsed
                    self.reset()
                }
                else {
                    /* Handle error. Usually just close the connection. */
                    self.release()
                    self.status.error = .parsedLessThanRead
                }
            }
            length -= numberParsed
        }
        status.bytesLeft = length
        
        return status
    }

    /// Read a chunk of the body of the message.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the message.
    /// - Throws: if an error occurs while reading the body.
    /// - Returns: the number of bytes read.
    public func read(into data: inout Data) throws -> Int {
        let count = bodyChunk.fill(data: &data)
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

    /// Read a chunk of the body and return it as a String.
    ///
    /// - Throws: if an error occurs while reading the data.
    /// - Returns: an Optional string.
    public func readString() throws -> String? {
        buffer.count = 0
        let length = try read(into: &buffer)
        if length > 0 {
            return String(data: buffer, encoding: .utf8)
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
    /// - Parameter bytes: The bytes of the parsed URL
    /// - Parameter count: The number of bytes parsed
    func onURL(_ bytes: UnsafePointer<UInt8>, count: Int) {
        pathAndQueryParams.append(bytes, count: count)
    }

    /// Instructions for when reading header key
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

    /// Instructions for when reading a header value
    ///
    /// - Parameter bytes: The bytes of the parsed header value
    /// - Parameter count: The number of bytes parsed
    func onHeaderValue (_ bytes: UnsafePointer<UInt8>, count: Int) {
        lastHeaderValue.append(bytes, length: count)

        lastHeaderWasAValue = true
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

    /// Instructions for when reading the body of the message
    ///
    /// - Parameter bytes: The bytes of the parsed body
    /// - Parameter count: The number of bytes parsed
    func onBody (_ bytes: UnsafePointer<UInt8>, count: Int) {
        self.bodyChunk.append(bytes: bytes, length: count)

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
        if  lastHeaderWasAValue  {
            addHeader()
        }

        if self is ServerRequest { // skip if ClientResponse
            var url = ""
            if let isSecure = signature?.isSecure {
                url.append(isSecure ? "https://" : "http://")
            } else {
                url.append("http://")
                Log.error("Socket signature not initialized, using http")
            }

            if let host = headers["Host"]?[0] {
                url.append(host)
            } else {
                url.append("Host_Not_Available")
                Log.error("Host header not received")
            }

            if let pathAndQueryParams = String(data: self.pathAndQueryParams, encoding: .utf8) {
                url.append(pathAndQueryParams)
            } else {
                url.append("/")
                Log.error("Invalid utf8 encoded path received in onURL: \(self.pathAndQueryParams)")
            }

            if let url = URL(string: url) {
                self.url = url
            } else {
                Log.error("URL init failed from parsed value: \(url)")
            }

            if let urlComponents = URLComponents(string: url) {
                self.urlComponents = urlComponents
            } else {
                Log.error("URLComponents init failed from parsed value: \(url)")
            }
        }

        status.keepAlive = httpParser?.isKeepAlive() ?? false
        status.state = .headersComplete
        
        httpStatusCode = httpParser?.statusCode ?? .unknown
    }

    /// Instructions for when beginning to read a message
    func onMessageBegin() {
    }

    /// Instructions for when done reading the message
    func onMessageComplete() {
        
        status.keepAlive = httpParser?.isKeepAlive() ?? false
        status.state = .messageComplete
        if  !status.keepAlive  {
            release()
        }
    }
    
    /// Signal that the connection is being closed, and resources should be freed
    func release() {
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
        pathAndQueryParams.count = 0
        url = nil
        urlComponents = URLComponents()
        headers.removeAll()
        bodyChunk.reset()
        status.reset()
        httpParser?.reset()
    }
}
