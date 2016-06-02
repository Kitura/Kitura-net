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
    /// Corresponding server request
    ///
    private weak var serverRequest : ServerRequest?

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
    init(socket: Socket, request: ServerRequest) {

        self.socket = socket
        serverRequest = request
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
        if let request = serverRequest {
            request.drain()
        }
        if  let socket = socket {
            try flushStart()
            if  buffer.length > 0  {
                try socket.write(from: buffer)
            }
            socket.close()
        }
        socket = nil
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

        try writeToSocketThroughBuffer(text: "HTTP/1.1 ")
        try writeToSocketThroughBuffer(text: String(status))
        try writeToSocketThroughBuffer(text: " ")
        var statusText = HTTP.statusCodes[status]

        if  statusText == nil {
            statusText = ""
        }

        try writeToSocketThroughBuffer(text: statusText!)
        try writeToSocketThroughBuffer(text: "\r\n")

        for (key, valueSet) in headers.headers {
            for value in valueSet {
                try writeToSocketThroughBuffer(text: key)
                try writeToSocketThroughBuffer(text: ": ")
                try writeToSocketThroughBuffer(text: value)
                try writeToSocketThroughBuffer(text: "\r\n")
            }
        }
        // We currently don't support keep alive
        try writeToSocketThroughBuffer(text: "Connection: Close\r\n")

        try writeToSocketThroughBuffer(text: "\r\n")
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
}
