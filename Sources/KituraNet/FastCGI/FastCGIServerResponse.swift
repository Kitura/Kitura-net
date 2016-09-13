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

/// The FastCGIServerRequest class implements the `ServerResponse` protocol
/// for incoming HTTP requests that come in over a FastCGI connection.
public class FastCGIServerResponse : ServerResponse {
 
    /// Socket for the ServerResponse
    private var socket: Socket?

    /// Size of buffers (64 * 1024 is the max size for a FastCGI outbound record)
    /// Which also gives a bit more internal buffer room.
    private static let bufferSize = 64 * 1024
    
    /// Buffer for HTTP response line, headers, and short bodies
    private var buffer = Data(capacity: FastCGIServerResponse.bufferSize)

    /// Whether or not the HTTP response line and headers have been flushed.
    private var startFlushed = false

    /// The headers to send back as part of the HTTP response.
    public var headers = HeadersContainer()
    
    /// Status code
    private var status = HTTPStatusCode.OK.rawValue
    
    /// Corresponding server request
    private weak var serverRequest : FastCGIServerRequest?
    
    /// The status code to send in the HTTP response.
    public var statusCode: HTTPStatusCode? {
        get {
            return HTTPStatusCode(rawValue: status)
        }
        set (newValue) {
            if let newValue = newValue, !startFlushed {
                status = newValue.rawValue
            }
        }
    }
    
    /// Initializes a `FastCGIServerResponse` instance
    ///
    /// - Parameter socket: The socket to write the ersponse to.
    /// - Parameter request: The `FastCGIServerRequest` object for the request that
    ///                     `FastCGIServerResponse` will respond to.
    init(socket: Socket, request: FastCGIServerRequest) {
        self.socket = socket
        self.serverRequest = request
        self.headers["Date"] = [SPIUtils.httpDate()]
    }
    
    /// Add a string to the body of the HTTP response and complete sending the HTTP response
    ///
    /// - Parameter text: The String to add to the body of the HTTP response.
    ///
    /// - Throws: Socket.error if an error occurred while writing to the socket
    public func end(text: String) throws {
        try write(from: text)
        try end()
    }

    /// Add a string to the body of the HTTP response.
    ///
    /// - Parameter string: The String data to be added.
    ///
    /// - Throws: Socket.error if an error occurred while writing to the socket
    public func write(from string: String) throws {
        try write(from: string.data(using: .utf8)!)
    }
    
    /// Add bytes to the body of the HTTP response.
    ///
    /// - Parameter data: The Data struct that contains the bytes to be added.
    ///
    /// - Throws: Socket.error if an error occurred while writing to the socket
    public func write(from data: Data) throws {
        
        try startResponse()
        
        if (buffer.count + data.count) > FastCGIServerResponse.bufferSize {
            try flush()
        }
        
        buffer.append(data)
    }
    
    /// Complete sending the HTTP response
    ///
    /// - Throws: Socket.error if an error occurred while writing to a socket
    public func end() throws {
        try startResponse()
        try concludeResponse()
    }
    
    /// Begin the buffer flush.
    ///
    /// This can only happen once and is called by all the tools that write
    /// data to the socket (from the implementation side). Effectively, this
    /// always happens before a buffer flush to make sure headers are written.
    ///
    /// Note that we can jump the queue internally to bypass this for writing
    /// FastCGI error messages.
    private func startResponse() throws {
        
        guard socket != nil && !startFlushed else {
            return
        }

        var headerData = ""

        // add our status header for FastCGI
        headerData.append("Status: \(status) \(HTTP.statusCodes[status]!)\r\n")

        // add the rest of our response headers
        for (_, entry) in headers.headers {
            for value in entry.value {
                headerData.append(entry.key)
                headerData.append(": ")
                headerData.append(value)
                headerData.append("\r\n")
            }
        }

        headerData.append("\r\n")
        
        try writeToSocket(headerData.data(using: .utf8)!)
        try flush()
        
        startFlushed = true
    }
    
    /// Get messages for FastCGI.
    private func getEndRequestMessage(requestId: UInt16, protocolStatus: UInt8) throws -> Data {
        
        let record = FastCGIRecordCreate()
        
        record.recordType = FastCGI.Constants.FCGI_END_REQUEST
        record.protocolStatus = protocolStatus
        record.requestId = requestId
        
        return try record.create()
        
    }
    
    /// Generate a "request complete" message to be transmitted to the server, indicating
    /// that the response is finished.
    private func getRequestCompleteMessage() throws -> Data {
        
        guard let serverRequest = self.serverRequest else {
            throw FastCGI.RecordErrors.internalError
        }
        
        return try getEndRequestMessage(requestId: serverRequest.requestId,
                                        protocolStatus: FastCGI.Constants.FCGI_REQUEST_COMPLETE)
        
    }

    /// Generate a "Can't Multiplex" messages for the specified request ID.
    /// This indicates to the calling web server that we won't be honoring requests
    /// beyond the first one until the first one is complete.
    private func getNoMultiplexingMessage(requestId: UInt16) throws -> Data {
        return try getEndRequestMessage(requestId: requestId, protocolStatus: FastCGI.Constants.FCGI_CANT_MPX_CONN)
    }

    /// Generate an "unsupported role" message. Indicates to the calling web server
    /// that we only intend to fulfill a specific role in the FastCGI chain (responder).
    private func getUnsupportedRoleMessage() throws -> Data? {
        
        guard let serverRequest = self.serverRequest else {
            throw FastCGI.RecordErrors.internalError
        }
        guard serverRequest.requestId != FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID else {
            throw FastCGI.RecordErrors.internalError
        }
        
        return try getEndRequestMessage(requestId: serverRequest.requestId, protocolStatus: FastCGI.Constants.FCGI_UNKNOWN_ROLE)
        
    }

    /// External message write for multiplex rejection
    ///
    /// - Parameter requestId: The id of the request to reject.
    public func rejectMultiplexConnecton(requestId: UInt16) throws {
        let message = try getNoMultiplexingMessage(requestId: requestId)
        try writeToSocket(message, wrapAsMessage: false)
    }
    
    /// External message write for role rejection
    public func rejectUnsupportedRole() throws {
        guard let message = try getUnsupportedRoleMessage() else {
            return
        }
        try writeToSocket(message, wrapAsMessage: false)
    }

    /// Reset the request for reuse in Keep alive
    public func reset() {
        /*****  TBD *******/
    }
    
    /// Get a FastCGI STDOUT message, wrapping the specified data
    /// for delivery.
    private func getMessage(buffer: Data?) throws -> Data {
        
        let record = FastCGIRecordCreate()
        
        record.recordType = FastCGI.Constants.FCGI_STDOUT
        record.requestId = serverRequest!.requestId
        
        if buffer != nil {
            record.data = buffer
        }
        
        return try record.create()
                
    }
    
    /// Write NSData to the socket
    private func writeToSocket(_ data: Data, wrapAsMessage: Bool = true) throws {

        guard let socket = socket else {
            return
        }

        if wrapAsMessage {
            try socket.write(from: getMessage(buffer: data))
        } else {
            try socket.write(from: data)
        }
        
    }
    
    /// Flush any data in the buffer to the socket, then
    /// reest the buffer for more data.
    private func flush() throws {
        
        guard buffer.count > 0 else {
            return
        }
    
        try writeToSocket(buffer)
        
        buffer.count = 0
        
    }
    
    /// Conclude this response.
    ///
    /// We're basically sending out anything left in the buffer, followed 
    /// by a blank STDOUT message, followed by an "END REQUEST" record with 
    /// "REQUEST COMPLETE" as it's protocol status.
    private func concludeResponse() throws {    
        
        // flush the reset of the buffer
        try flush()
        
        // send a blank packet
        try writeToSocket(getMessage(buffer: nil), wrapAsMessage: false)
        
        // send done
        try writeToSocket(getRequestCompleteMessage(), wrapAsMessage: false)
        
        // close the socket.
        // we presently don't support keep-alive so this is fine.
        if let socket = self.socket {
            socket.close()
        }
        self.socket = nil
    }

}
