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

// MARK: ServerResponse

public class ServerResponse : SocketWriter {

    ///
    /// Socket for the ServerResponse
    ///
    private var socket: Socket?

    ///
    /// Size of buffer
    ///
    private static let bufferSize = 2000

    ///
    /// Buffer for HTTP response line, headers, and short bodies
    ///
    private var buffer: NSMutableData

    ///
    /// Whether or not the HTTP response line and headers have been flushed.
    ///
    private var startFlushed = false

    ///
    /// TODO: ???
    ///
    public var headers = HeadersContainer()
    
    ///
    /// Status code
    ///
    private var status = HTTPStatusCode.OK.rawValue
    
    ///
    /// Corresponding socket handler
    ///
    private weak var handler : IncomingHTTPSocketHandler?

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
    /// Initializes a ServerResponse instance
    ///
    init(socket: Socket, handler: IncomingHTTPSocketHandler) {

        self.socket = socket
        self.handler = handler
        buffer = NSMutableData(capacity: ServerResponse.bufferSize)!
        headers["Date"] = [SPIUtils.httpDate()]
    }

    ///
    /// Write a string as a response
    ///
    /// - Parameter string: String data to be written.
    ///
    /// - Throws: ???
    ///
    public func write(from string: String) throws {

        if  socket != nil  {
            try flushStart()
            try writeToSocketThroughBuffer(text: string)
        }

    }

    ///
    /// Write data as a response
    ///
    /// - Parameter data: NSMutableData object to contain read data.
    ///
    /// - Returns: Integer representing the number of bytes read.
    ///
    /// - Throws: ???
    ///
    public func write(from data: NSData) throws {

        if  let socket = socket {
            try flushStart()
            if  buffer.length + data.length > ServerResponse.bufferSize  &&  buffer.length != 0  {
                try socket.write(from: buffer)
                buffer.length = 0
            }
            if  data.length > ServerResponse.bufferSize {
                try socket.write(from: data)
            }
            else {
                buffer.append(data)
            }
        }

    }

    ///
    /// End the response
    ///
    /// - Parameter text: String to write out socket
    ///
    /// - Throws: ???
    ///
    public func end(text: String) throws {
        try write(from: text)
        try end()
    }
    
    ///
    /// End sending the response
    ///
    /// - Throws: ???
    ///
    public func end() throws {
        if let handler = handler {
            handler.drain()
        }
        if  let socket = socket {
            try flushStart()
            
            let keepAlive = handler?.isKeepAlive ?? false
            if  keepAlive {
                handler?.keepAlive()
            }
            
            if  buffer.length > 0  {
                try socket.write(from: buffer)
            }
            
            if keepAlive {
                reset()
            }
            else {
                socket.close()
                self.socket = nil
            }
        }
    }
    
    ///
    /// Begin flushing the buffer
    ///
    /// - Throws: ???
    ///
    private func flushStart() throws {

        if  socket == nil  ||  startFlushed  {
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
        let keepAlive = handler?.isKeepAlive ?? false
        if  keepAlive {
            headerData.append("Connection: Keep-Alive\r\n")
            headerData.append("Keep-Alive: timeout=\(Int(IncomingHTTPSocketHandler.keepAliveTimeout)), max=\((handler?.numberOfRequests ?? 1) - 1)\r\n")
        }
        else {
            headerData.append("Connection: Close\r\n")
        }
        
        headerData.append("\r\n")
        try writeToSocketThroughBuffer(text: headerData)
        startFlushed = true
    }

    ///
    /// Function to write Strings to the socket through the buffer
    ///
    private func writeToSocketThroughBuffer(text: String) throws {
        guard let socket = socket,
              let utf8Data = StringUtils.toUtf8String(text) else {
            return
        }

        if  buffer.length + utf8Data.length > ServerResponse.bufferSize  &&  buffer.length != 0  {
            try socket.write(from: buffer)
            buffer.length = 0
        }
        if  utf8Data.length > ServerResponse.bufferSize {
            try socket.write(from: utf8Data)
        }
        else {
            buffer.append(utf8Data)
        }
    }
    
    ///
    /// Reset this response object back to it's initial state
    ///
    private func reset() {
        status = HTTPStatusCode.OK.rawValue
        buffer.length = 0
        startFlushed = false
        headers.removeAll()
        headers["Date"] = [SPIUtils.httpDate()]
    }
}
