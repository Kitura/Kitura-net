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
public class HTTPIncomingMessage {

    /// HTTP Status code if this message is a response
    public private(set) var httpStatusCode: HTTPStatusCode = .unknown

    /// is a request? (or a response)
    public let isRequest: Bool

    /// Client connection socket
    private let socket: Socket?
    
    /// HTTP Method of the incoming message.
    public var method: String { return httpParser.method }
    
    /// Major version of HTTP of the request
    public var httpVersionMajor: UInt16? { return httpParser.httpVersionMajor }
    
    /// Minor version of HTTP of the request
    public var httpVersionMinor: UInt16? { return httpParser.httpVersionMinor }
    
    /// Set of HTTP headers of the incoming message.
    public var headers: HeadersContainer { return httpParser.headers }

    /// socket signature of the request.
    public var signature: Socket.Signature? { return socket?.signature }

    private var _url: URL?
    
    public var urlURL: URL {
        if let _url = _url {
            return _url
        }
        
        var url = ""
        var proto: String?
        if let isSecure = signature?.isSecure {
            proto = (isSecure ? "https" : "http")
            url.append(proto! + "://")
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
        
        url.append(httpParser.urlString)
        
        if let urlURL = URL(string: url) {
            self._url = urlURL
        } else {
            Log.error("URL init failed from: \(url)")
            self._url = URL(string: "http://not_available/")!
        }
        
        return self._url!
    }

    private var urlc: URLComponents?

    /// The URL from the request as URLComponents
    /// URLComponents has a memory leak on linux as of swift 3.0.1. Use 'urlURL' instead
    @available(*, deprecated, message:
        "URLComponents has a memory leak on linux as of swift 3.0.1. use 'urlURL' instead")
    public var urlComponents: URLComponents {
        if let urlc = self.urlc {
            return urlc
        }
        let urlc = URLComponents(url: self.urlURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        self.urlc = urlc
        return urlc
    }
    
    /// The URL from the request in string form
    /// This contains just the path and query parameters starting with '/'
    /// Use 'urlURL' for the full URL
    @available(*, deprecated, message:
        "This contains just the path and query parameters starting with '/'. use 'urlURL' instead")
    public var urlString : String { return httpParser.urlString }

    /// The URL from the request in UTF-8 form
    /// This contains just the path and query parameters starting with '/'
    /// Use 'urlURL' for the full URL
    @available(*, deprecated, message:
        "This contains just the path and query parameters starting with '/'. use 'urlURL' instead")
    public var url : Data { return Data(bytes: httpParser.url.bytes, count: httpParser.url.length) }

    // Private
    
    /// Default buffer size used for creating a BufferList
    private static let bufferSize = 2000

    /// The http_parser Swift wrapper
    private var httpParser: HTTPParser!

    /// State of incoming message handling
    private var status = HTTPParserStatus()

    private var buffer = Data(capacity: HTTPIncomingMessage.bufferSize)
    
    /// Initializes a new IncomingMessage
    ///
    /// - Parameter isRequest: whether this message is a request
    ///
    /// - Returns: an IncomingMessage instance
    init (isRequest: Bool, socket: Socket? = nil) {
        self.isRequest = isRequest
        self.socket = socket
        httpParser = HTTPParser(isRequest: isRequest)
    }

    /// Parse the message
    ///
    /// - Parameter buffer: An NSData object contaning the data to be parsed
    /// - Parameter from: From where in the buffer to start parsing
    /// - Parameter completeBuffer: An indication that the complete buffer is being passed in.
    ///                            If true and the entire buffer is parsed, an EOF indication
    ///                            will be passed to the http_parser.
    func parse (_ buffer: NSData, from: Int, completeBuffer: Bool=false) -> HTTPParserStatus {
        let length = buffer.length - from
        
        guard length > 0  else {
            /* Handle unexpected EOF. Usually just close the connection. */
            status.error = .unexpectedEOF
            return status
        }
        
        // If we were reset because of keep alive
        if  status.state == .reset  {
            reset()
        }
        
        let bytes = buffer.bytes.assumingMemoryBound(to: Int8.self) + from
        let (numberParsed, upgrade) = httpParser.execute(bytes, length: length)
        
        if completeBuffer && numberParsed == length {
            // Tell parser we reached the end
            _ = httpParser.execute(bytes, length: 0)
        }
        
        if httpParser.completed {
            parsingCompleted()
        }
        else if numberParsed != length  {
            /* Handle error. Usually just close the connection. */
            status.error = .parsedLessThanRead
        }
        
        if upgrade == 1 {
            status.upgrade = true
        }
        
        status.bytesLeft = length - numberParsed
        
        return status
    }

    /// Read a chunk of the body of the message.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the message.
    /// - Throws: if an error occurs while reading the body.
    /// - Returns: the number of bytes read.
    public func read(into data: inout Data) throws -> Int {
        let count = httpParser.bodyChunk.fill(data: &data)
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

    /// Extra handling performed when a message is completely parsed
    func parsingCompleted() {
        
        if isRequest {

            _url = nil // reset it so it is recomputed on next access
            urlc = nil // reset it so it is recomputed on next access

            if Log.isLogging(.verbose) {
                var proto: String?
                if let isSecure = signature?.isSecure {
                    proto = (isSecure ? "https" : "http")
                } else {
                    Log.error("Socket signature not initialized, using http")
                }
                
                if let forwardedFor = headers["X-Forwarded-For"]?[0] {
                    Log.verbose("HTTP request forwarded for=\(forwardedFor); proto=\(headers["X-Forwarded-Proto"]?[0] ?? "N.A."); by=\(socket?.remoteHostname ?? "N.A.");")
                } else {
                    Log.verbose("HTTP request from=\(socket?.remoteHostname ?? "N.A."); proto=\(proto ?? "N.A.");")
                }
            }
        }

        status.keepAlive = httpParser.isKeepAlive() 
        status.state = .messageComplete
        
        httpStatusCode = httpParser.statusCode
    }

    /// Signal that reading is being reset
    func prepareToReset() {
        status.state = .reset
    }

    /// When we're ready, really reset everything
    private func reset() {
        status.reset()
        httpParser?.reset()
    }
}
