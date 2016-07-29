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

import Foundation

// MARK: HTTPServerResponse

public class HTTPServerResponse : ServerResponse {

    /// Size of buffer
    private static let bufferSize = 2000

    /// Buffer for HTTP response line, headers, and short bodies
    private var buffer: NSMutableData

    /// Whether or not the HTTP response line and headers have been flushed.
    private var startFlushed = false

    ///
    /// The headers to be sent to the client as part of the response
    ///
    public var headers = HeadersContainer()
    
    ///
    /// Status code
    ///
    private var status = HTTPStatusCode.OK.rawValue
    
    ///
    /// Corresponding socket processor
    ///
    private weak var processor : IncomingHTTPSocketProcessor?

    ///
    /// Status code
    ///
    public var statusCode: HTTPStatusCode? {
        get {
            return HTTPStatusCode(rawValue: status)
        }
        set (newValue) {
            if let newValue = newValue where !startFlushed {
                status = newValue.rawValue
            }
        }
    }

    ///
    /// Initializes a HTTPServerResponse instance
    ///
    init(processor: IncomingHTTPSocketProcessor) {

        self.processor = processor
        buffer = NSMutableData(capacity: HTTPServerResponse.bufferSize)!
        headers["Date"] = [SPIUtils.httpDate()]
    }

    ///
    /// Write a string as a response
    ///
    /// - Parameter string: String data to be written.
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    ///
    public func write(from string: String) throws {

        try flushStart()
        try writeToSocketThroughBuffer(text: string)

    }

    ///
    /// Write data as a response
    ///
    /// - Parameter data: NSMutableData object to contain read data.
    ///
    /// - Returns: Integer representing the number of bytes read.
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    ///
    public func write(from data: NSData) throws {

        if  let processor = processor {
            try flushStart()
            if  buffer.length + data.length > HTTPServerResponse.bufferSize  &&  buffer.length != 0  {
                processor.write(from: buffer)
                buffer.length = 0
            }
            if  data.length > HTTPServerResponse.bufferSize {
                processor.write(from: data)
            }
            else {
                #if os(Linux)
                    buffer.append(data)
                #else
                    buffer.append(data as Data)
                #endif
            }
        }

    }

    ///
    /// End the response
    ///
    /// - Parameter text: String to write out socket
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    ///
    public func end(text: String) throws {
        try write(from: text)
        try end()
    }
    
    ///
    /// End sending the response
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    ///
    public func end() throws {
        if let processor = processor {
            processor.drain()
        
            try flushStart()
            
            let keepAlive = processor.isKeepAlive ?? false
            if  keepAlive {
                processor.keepAlive()
            }
            
            if  buffer.length > 0  {
                processor.write(from: buffer)
            }
            
            if !keepAlive  {
                processor.close()
            }
        }
    }

    /// Begin flushing the buffer
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    private func flushStart() throws {

        if  startFlushed  {
            return
        }

        var headerData = ""
        headerData.append("HTTP/1.1 ")
        headerData.append(String(status))
        headerData.append(" ")
        var statusText = HTTP.statusCodes[status]

        if  statusText == nil {
            statusText = ""
        }

        headerData.append(statusText!)
        headerData.append("\r\n")

        for (key, valueSet) in headers.headers {
            for value in valueSet {
                headerData.append(key)
                headerData.append(": ")
                headerData.append(value)
                headerData.append("\r\n")
            }
        }
        let keepAlive = processor?.isKeepAlive ?? false
        if  keepAlive {
            headerData.append("Connection: Keep-Alive\r\n")
            headerData.append("Keep-Alive: timeout=\(Int(IncomingHTTPSocketProcessor.keepAliveTimeout)), max=\((processor?.numberOfRequests ?? 1) - 1)\r\n")
        }
        else {
            headerData.append("Connection: Close\r\n")
        }
        
        headerData.append("\r\n")
        try writeToSocketThroughBuffer(text: headerData)
        startFlushed = true
    }

    /// Function to write Strings to the socket through the buffer
    ///
    /// Throws: Socket.error if an error occurred while writing to a socket
    private func writeToSocketThroughBuffer(text: String) throws {
        guard let processor = processor,
              let utf8Data = StringUtils.toUtf8String(text) else {
            return
        }

        if  buffer.length + utf8Data.length > HTTPServerResponse.bufferSize  &&  buffer.length != 0  {
            processor.write(from: buffer)
            buffer.length = 0
        }
        if  utf8Data.length > HTTPServerResponse.bufferSize {
            processor.write(from: utf8Data)
        }
        else {
            #if os(Linux)
                buffer.append(utf8Data)
            #else
                buffer.append(utf8Data as Data)
            #endif
        }
    }
    
    /// Reset this response object back to it's initial state
    public func reset() {
        status = HTTPStatusCode.OK.rawValue
        buffer.length = 0
        startFlushed = false
        headers.removeAll()
        headers["Date"] = [SPIUtils.httpDate()]
    }
}
