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
import LoggerAPI

// MARK: ClientResponse

/// This class describes the response sent by the remote server to an HTTP request
/// sent using the `ClientRequest` class.
public class ClientResponse {
    
    /// HTTP Status code
    public private(set) var httpStatusCode: HTTPStatusCode = .unknown
    
    /// HTTP Method of the incoming message.
    @available(*, deprecated, message:
    "This method never worked on Client Responses and was inherited incorrectly from a super class")
    public var method: String { return httpParser.method }
    
    /// Major version of HTTP of the response
    public var httpVersionMajor: UInt16? { return httpParser.httpVersionMajor }
    
    /// Minor version of HTTP of the response
    public var httpVersionMinor: UInt16? { return httpParser.httpVersionMinor }
    
    /// Set of HTTP headers of the response.
    public var headers: HeadersContainer { return httpParser.headers }
    
    // Private
    
    /// Default buffer size used for creating a BufferList
    private static let bufferSize = 2000
    
    /// The http_parser Swift wrapper
    private var httpParser = HTTPParser(isRequest: false)
    
    /// State of response parsing
    private var parserStatus = HTTPParserStatus()
    
    private var buffer = Data(capacity: bufferSize)
    
    /// Parse the message
    ///
    /// - Parameter buffer: An NSData object contaning the data to be parsed
    /// - Parameter from: From where in the buffer to start parsing
    func parse (_ buffer: NSData, from: Int) -> HTTPParserStatus {
        let length = buffer.length - from
        
        guard length > 0  else {
            /* Handle unexpected EOF. Usually just close the connection. */
            parserStatus.error = .unexpectedEOF
            return parserStatus
        }
        
        // If we were reset because of keep alive
        if  parserStatus.state == .reset  {
            reset()
        }
        
        let bytes = buffer.bytes.assumingMemoryBound(to: Int8.self) + from
        let (numberParsed, _) = httpParser.execute(bytes, length: length)
        
        if numberParsed == length {
            // Tell parser we reached the end
            _ = httpParser.execute(bytes, length: 0)
        }
        
        if httpParser.completed {
            parsingCompleted()
        }
        else if numberParsed != length  {
            /* Handle error. Usually just close the connection. */
            parserStatus.error = .parsedLessThanRead
        }
        
        parserStatus.bytesLeft = length - numberParsed
        
        return parserStatus
    }
    
    /// Read a chunk of the body of the response.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the response.
    /// - Throws: if an error occurs while reading the body.
    /// - Returns: the number of bytes read.
    public func read(into data: inout Data) throws -> Int {
        let count = httpParser.bodyChunk.fill(data: &data)
        return count
    }
    
    /// Read the whole body of the response.
    ///
    /// - Parameter into: An NSMutableData to hold the data in the response.
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
        
        parserStatus.keepAlive = httpParser.isKeepAlive()
        parserStatus.state = .messageComplete
        
        httpStatusCode = httpParser.statusCode
    }
    
    /// Signal that reading is being reset
    func prepareToReset() {
        parserStatus.state = .reset
    }
    
    /// When we're ready, really reset everything
    private func reset() {
        parserStatus.reset()
        httpParser.reset()
    }

    /// Initializes a `ClientResponse` instance
    init() {
    }
    
    /// The HTTP Status code, as an Int, sent in the response by the remote server.
    public internal(set) var status = -1 {
        
        didSet {
            statusCode = HTTPStatusCode(rawValue: status)!
        }
        
    }
 
    /// The HTTP Status code, as an `HTTPStatusCode`, sent in the response by the remote server.
    public internal(set) var statusCode: HTTPStatusCode = HTTPStatusCode.unknown
    
    /// BufferList instance for storing the response 
    var responseBuffers = BufferList()
    
    /// Location in buffer to start parsing
    private var startParsingFrom = 0
    
    /// Parse the contents of the responseBuffers
    func parse() -> HTTPParserStatus {
        let buffer = NSMutableData()
        responseBuffers.rewind()
        _ = responseBuffers.fill(data: buffer)
        
        // There can be multiple responses in the responseBuffers, if a Continue response
        // was received from the server. Each call to this function parses a single
        // response, starting from the prior parse call, if any, left off. when this
        // happens, the http_parser needs to be reset between invocations.
        prepareToReset()
        
        let parseStatus = parse(buffer, from: startParsingFrom)
        
        startParsingFrom = buffer.length - parseStatus.bytesLeft
        
        return parseStatus
    }
}
