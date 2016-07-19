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

import Foundation
import Socket
import KituraSys

public class FastCGIServerResponse : ServerResponse {
 
    ///
    /// Socket for the ServerResponse
    ///
    private var socket: Socket?

    ///
    /// Size of buffers (64 * 1024 is the max size for a FastCGI outbound record)
    /// Which also gives a bit more internal buffer room.
    ///
    private static let bufferSize = 64 * 1024
    
    ///
    /// Buffer for HTTP response line, headers, and short bodies
    ///
    private let buffer: NSMutableData = NSMutableData(capacity: FastCGIServerResponse.bufferSize)!

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
    private weak var serverRequest : FastCGIServerRequest?
    
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
    init(socket: Socket, request: FastCGIServerRequest) {
        self.socket = socket
        self.serverRequest = request
        headers["Date"] = [SPIUtils.httpDate()]
    }
    
    
    // 
    // The following write and end methods are basically convenience methods
    // They rely on other methods to do their work.
    //
    public func end(text: String) throws {
        try self.write(from: text)
        try end()
    }

    public func write(from string: String) throws {
        try self.write(from: StringUtils.toUtf8String(string)!)
    }
    
    //
    // Actual write methods
    //
    public func write(from data: NSData) throws {
        
        try startResponse()
        
        if (self.buffer.length + data.length) > FastCGIServerResponse.bufferSize {
            try flush()
        }
        
        #if os(Linux)
            self.buffer.append(data)
        #else
            self.buffer.append(data as Data)
        #endif
    }
    
    public func end() throws {
        try startResponse()
        try concludeResponse()
    }
    
    ///
    /// Begin the buffer flush.
    ///
    /// This can only happen once and is called by all the tools that write
    /// data to the socket (from the implementation side). Effectively, this
    /// always happens before a buffer flush to make sure headers are written.
    ///
    /// Note that we can jump the queue internally to bypass this for writing
    /// FastCGI error messages.
    ///
    private func startResponse() throws {
        
        guard socket != nil && !startFlushed else {
            return
        }

        var headerData = ""

        // add our status header for FastCGI
        headerData.append("Status: \(self.status) \(HTTP.statusCodes[self.status]!)\r\n")

        // add the rest of our response headers
        for (key, valueSet) in headers.headers {
            for value in valueSet {
                headerData.append(key)
                headerData.append(": ")
                headerData.append(value)
                headerData.append("\r\n")
            }
        }

        headerData.append("\r\n")
        
        try writeToSocket(StringUtils.toUtf8String(headerData)!)
        try flush()
        
        startFlushed = true
    }
    
    /// 
    /// Get messages for FastCGI.
    ///
    private func getEndRequestMessage(requestId: UInt16, protocolStatus: UInt8) throws -> NSData {
        
        let record = FastCGIRecordCreate()
        
        record.recordType = FastCGI.Constants.FCGI_END_REQUEST
        record.protocolStatus = protocolStatus
        record.requestId = requestId
        
        return try record.create()
        
    }
    
    //
    // Generate a "request complete" message to be transmitted to the server, indicating 
    // that the response is finished.
    //
    private func getRequestCompleteMessage() throws -> NSData {
        
        guard let serverRequest = self.serverRequest else {
            throw FastCGI.RecordErrors.internalError
        }
        
        return try self.getEndRequestMessage(requestId: serverRequest.requestId,
                                             protocolStatus: FastCGI.Constants.FCGI_REQUEST_COMPLETE)
        
    }

    //
    // Generate a "Can't Multiplex" messages for the specified request ID. 
    // This indicates to the calling web server that we won't be honoring requests
    // beyond the first one until the first one is complete.
    //
    private func getNoMultiplexingMessage(requestId: UInt16) throws -> NSData {
        return try self.getEndRequestMessage(requestId: requestId, protocolStatus: FastCGI.Constants.FCGI_CANT_MPX_CONN)
    }

    //
    // Generate an "unsupported role" message. Indicaes to the calling web server
    // that we only intend to fulfill a specific role in the FastCGI chain (responder).
    //
    private func getUnsupportedRoleMessage() throws -> NSData? {
        
        guard let serverRequest = self.serverRequest else {
            throw FastCGI.RecordErrors.internalError
        }
        guard let requestId : UInt16 = serverRequest.requestId else {
            throw FastCGI.RecordErrors.internalError
        }
        guard requestId != FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID else {
            throw FastCGI.RecordErrors.internalError
        }
        
        return try self.getEndRequestMessage(requestId: requestId, protocolStatus: FastCGI.Constants.FCGI_UNKNOWN_ROLE)
        
    }

    ///
    /// External message write for multiplex rejection    
    ///
    public func rejectMultiplexConnecton(requestId: UInt16) throws {
        guard let message : NSData = try self.getNoMultiplexingMessage(requestId: requestId) else {
            return
        }
        try self.writeToSocket(message, wrapAsMessage: false)
    }
    
    /// 
    /// External message write for role rejection
    ///
    public func rejectUnsupportedRole() throws {
        guard let message : NSData = try self.getUnsupportedRoleMessage() else {
            return
        }
        try self.writeToSocket(message, wrapAsMessage: false)
    }
    
    ///
    /// Get a FastCGI STDOUT message, wrapping the specified data
    /// for delivery.
    ///
    private func getMessage(buffer: NSData?) throws -> NSData {
        
        let record = FastCGIRecordCreate()
        
        record.recordType = FastCGI.Constants.FCGI_STDOUT
        record.requestId = self.serverRequest!.requestId
        
        if (buffer != nil) {
            record.data = buffer
        }
        
        return try record.create()
                
    }
    
    ///
    /// Write NSData to the socket
    ///
    private func writeToSocket(_ data: NSData, wrapAsMessage: Bool = true) throws {

        guard let socket = socket else {
            return
        }

        if (wrapAsMessage) {
            try socket.write(from: getMessage(buffer: data))
        } else {
            try socket.write(from: data)
        }
        
    }
    
    ///
    /// Flush any data in the buffer to the socket, then
    /// reest the buffer for more data.
    ///
    private func flush() throws {
        
        guard self.buffer.length > 0 else {
            return
        }
    
        try self.writeToSocket(self.buffer)
        self.buffer.length = 0
        
    }
    
    ///
    /// Conclude this response.
    ///
    /// We're basically sending out anything left in the buffer, followed 
    /// by a blank STDOUT message, followed by an "END REQUEST" record with 
    /// "REQUEST COMPLETE" as it's protocol status.
    ///
    private func concludeResponse() throws {    
        
        // flush the reset of the buffer
        try self.flush()
        
        // send a blank packet
        try self.writeToSocket(getMessage(buffer: nil), wrapAsMessage: false)
        
        // send done
        try self.writeToSocket(getRequestCompleteMessage(), wrapAsMessage: false)
        
        // close the socket.
        // we presently don't support keep-alive so this is fine.
        if let socket = self.socket {
            socket.close()
        }
        self.socket = nil
    }

}
