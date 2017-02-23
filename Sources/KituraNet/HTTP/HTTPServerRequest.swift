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
import Socket
import LoggerAPI

// MARK: HTTPServerRequest

/// This class implements the `ServerRequest` protocol for incoming sockets that
/// are communicating via the HTTP protocol. 
public class HTTPServerRequest: ServerRequest {
    
    /// HTTP Status code if this message is a response
    @available(*, deprecated, message:
    "This method never worked on Server Requests and was inherited incorrectly from a super class")
    public private(set) var httpStatusCode: HTTPStatusCode = .unknown
    
    /// Client connection socket
    private let socket: Socket
    
    /// Server IP address pulled from socket.
    public var remoteAddress: String {
        return socket.remoteHostname
    }
    
    /// HTTP Method of the request.
    public var method: String { return httpParser?.method ?? ""}
    
    /// Major version of HTTP of the request
    public var httpVersionMajor: UInt16? { return httpParser?.httpVersionMajor ?? 0}
    
    /// Minor version of HTTP of the request
    public var httpVersionMinor: UInt16? { return httpParser?.httpVersionMinor ?? 0}
    
    /// Set of HTTP headers of the request.
    public var headers: HeadersContainer { return httpParser?.headers ?? HeadersContainer() }
    
    /// socket signature of the request.
    public var signature: Socket.Signature? { return socket.signature }
    
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
        
        url.append(httpParser?.urlString ?? "")
        
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
    public var urlString : String { return httpParser?.urlString ?? ""}
    
    /// The URL from the request in UTF-8 form
    /// This contains just the path and query parameters starting with '/'
    /// Use 'urlURL' for the full URL
    public var url : Data {
        if let httpParser = httpParser {
            return  Data(bytes: httpParser.url.bytes, count: httpParser.url.length)
        }
        return Data()
    }
    
    // Private
    
    /// Default buffer size used for creating a BufferList
    private static let bufferSize = 2000
    
    /// The http_parser Swift wrapper
    weak var httpParser: HTTPParser?
    
    /// State of parsing the request
    private var status = HTTPParserStatus()
    
    private var buffer = Data(capacity: bufferSize)
    
    /// Initializes a new `HTTPServerRequest`
    ///
    /// - Parameter socket: The Socket object associated with this request
    /// - Parameter httpParser: The `HTTPParser` object used to parse the incoming request
    ///
    /// - Returns: an HTTPServerRequest instance
    init (socket: Socket, httpParser: HTTPParser?) {
        self.socket = socket
        self.httpParser = httpParser
    }
    
    /// Read a chunk of the body of the request.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the request.
    /// - Throws: if an error occurs while reading the body.
    /// - Returns: the number of bytes read.
    public func read(into data: inout Data) throws -> Int {
        guard let httpParser = httpParser else {
            return 0
        }
        
        let count = httpParser.bodyChunk.fill(data: &data)
        return count
    }
    
    /// Read the whole body of the request.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the request.
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
        
        guard let httpParser = httpParser else {
            Log.error("Parser nil")
            return
        }
        
        
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
                Log.verbose("HTTP request forwarded for=\(forwardedFor); proto=\(headers["X-Forwarded-Proto"]?[0] ?? "N.A."); by=\(socket.remoteHostname );")
            } else {
                Log.verbose("HTTP request from=\(socket.remoteHostname); proto=\(proto ?? "N.A.");")
            }
        }
        
        status.keepAlive = httpParser.isKeepAlive()
        status.state = .messageComplete
    }

}
