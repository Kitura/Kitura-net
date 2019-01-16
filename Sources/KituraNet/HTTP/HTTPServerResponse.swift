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

// MARK: HTTPServerResponse

/**
This class implements the `ServerResponse` protocol for outgoing server
responses via the HTTP protocol. Data and Strings can be written.
 
The example below uses this in its `response` parameter, with the example requesting a connection be upgraded and catch any errors that occur.

### Usage Example: ###
````swift
 func upgradeConnection(handler: IncomingSocketHandler, request: ServerRequest, response: ServerResponse) {
     guard let protocols = request.headers["Upgrade"] else {
         do {
             response.statusCode = HTTPStatusCode.badRequest
             try response.write(from: "No protocol specified in the Upgrade header")
             try response.end()
         }
         catch {
             Log.error("Failed to send error response to Upgrade request")
         }
         return
     }
 }
````
*/
public class HTTPServerResponse : ServerResponse {

    /// Size of buffer
    private static let bufferSize = 2000

    /// Buffer for HTTP response line, headers, and short bodies
    private var buffer: NSMutableData

    /// Whether or not the HTTP response line and headers have been flushed.
    private var startFlushed = false

    /**
    The HTTP headers to be sent to the client as part of the response.
    
    ### Usage Example: ###
    ````swift
    ServerResponse.headers["Content-Type"] = ["text/plain"]
    ````
    */
    public var headers = HeadersContainer()
    
    /// Status code
    private var status = HTTPStatusCode.OK.rawValue
    
    /// Corresponding socket processor
    private weak var processor : IncomingHTTPSocketProcessor?
    
    let request: HTTPServerRequest?

    /**
    HTTP status code of the response.
    
    ### Usage Example: ###
    ````swift
    ServerResponse.statusCode = HTTPStatusCode.badRequest
    ````
    */
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

    /// Initializes a HTTPServerResponse instance
    init(processor: IncomingHTTPSocketProcessor, request: HTTPServerRequest?) {
        self.processor = processor
        buffer = NSMutableData(capacity: HTTPServerResponse.bufferSize) ?? NSMutableData()
        headers["Date"] = [SPIUtils.httpDate()]
        self.request = request
    }

    /**
    Write a string as a response.
    
    - Parameter from: String data to be written.
    - Throws: Socket.error if an error occurred while writing to a socket.
    
    ### Usage Example: ###
    ````swift
     try ServerResponse.write(from: "Some string")
    ````
    */
    public func write(from string: String) throws {
        try flushStart()
        try writeToSocketThroughBuffer(text: string)
    }

    /**
    Write data as a response.
    
    - Parameter from: Data object that contains the data to be written.
    - Throws: Socket.error if an error occurred while writing to a socket.
    
    ### Usage Example: ###
    ````swift
    try ServerResponse.write(from: someData)
    ````
    */
    public func write(from data: Data) throws {
        if  let processor = processor {
            try flushStart()
            if  buffer.length + data.count > HTTPServerResponse.bufferSize  &&  buffer.length != 0  {
                processor.write(from: buffer)
                buffer.length = 0
            }
            if  data.count > HTTPServerResponse.bufferSize {
                let dataToWrite = NSData(data: data)
                processor.write(from: dataToWrite)
            }
            else {
                buffer.append(data)
            }
        }
    }

    /**
    Write a String to the body of a HTTP response and complete sending the HTTP response.
    
    - Parameter text: String to write to a socket.
    - Throws: Socket.error if an error occurred while writing to a socket.
    
    ### Usage Example: ###
    ````swift
    try ServerResponse.end("Some string")
    ````
    */
    public func end(text: String) throws {
        try write(from: text)
        try end()
    }
    
    /**
    Complete sending the HTTP response.
    
    - Throws: Socket.error if an error occurred while writing to a socket.
    
    ### Usage Example: ###
    ````swift
    try ServerResponse.end()
    ````
    */
    public func end() throws {
        if let processor = processor {
            try flushStart()
            if  buffer.length > 0  {
                processor.write(from: buffer)
            }
            let keepAlive = processor.isKeepAlive
            if !keepAlive && !processor.isUpgrade {
                processor.close()
            }
            if let request = request {
                Monitor.delegate?.finished(request: request, response: self)
            }
            // Ordering is important here. Keepalive allows the processor to continue
            // processing further requests, so must only be called once monitoring
            // has completed, as the HTTPParser for this connection is reused.
            if  keepAlive {
                processor.keepAlive()
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
        headerData.reserveCapacity(254)
        headerData.append("HTTP/1.1 ")
        headerData.append(String(status))
        headerData.append(" ")
        var statusText = HTTP.statusCodes[status]

        if  statusText == nil {
            statusText = ""
        }

        headerData.append(statusText!)
        headerData.append("\r\n")

        for (_, entry) in headers.headers {
            for value in entry.value {
                headerData.append(entry.key)
                headerData.append(": ")
                headerData.append(value)
                headerData.append("\r\n")
            }
        }
        
        let upgrade = processor?.isUpgrade ?? false
        let keepAlive = processor?.isKeepAlive ?? false
        if !upgrade {
            if  keepAlive {
                headerData.append("Connection: Keep-Alive\r\n")
                headerData.append("Keep-Alive: timeout=\(Int(IncomingHTTPSocketProcessor.keepAliveTimeout))")
                if let numberOfRequests = processor?.keepAliveState.requestsRemaining {
                    headerData.append(", max=\(numberOfRequests)")
                }
                headerData.append("\r\n")
            }
            else {
                headerData.append("Connection: Close\r\n")
            }
        }
        
        headerData.append("\r\n")
        try writeToSocketThroughBuffer(text: headerData)
        startFlushed = true
    }

    /// Function to write Strings to the socket through the buffer
    ///
    /// Throws: Socket.error if an error occurred while writing to a socket
    private func writeToSocketThroughBuffer(text: String) throws {
        guard let processor = processor else {
            return
        }
        
        let utf8Length = text.utf8.count
        var utf8: [CChar] = Array<CChar>(repeating: 0, count: utf8Length + 10) // A little bit of padding
        guard text.getCString(&utf8, maxLength: utf8Length + 10, encoding: .utf8)  else {
            return
        }
        
        if  buffer.length + utf8.count > HTTPServerResponse.bufferSize  &&  buffer.length != 0  {
            processor.write(from: buffer)
            buffer.length = 0
        }
        if  utf8.count > HTTPServerResponse.bufferSize {
            processor.write(from: utf8, length: utf8Length)
        }
        else {
            buffer.append(UnsafePointer(utf8), length: utf8Length)
        }
    }
    
    /**
    Reset this response object back to its initial state.
    
    ### Usage Example: ###
    ````swift
    try ServerResponse.reset()
    ````
    */
    public func reset() {
        status = HTTPStatusCode.OK.rawValue
        buffer.length = 0
        startFlushed = false
        headers.removeAll()
        headers["Date"] = [SPIUtils.httpDate()]
    }
}
