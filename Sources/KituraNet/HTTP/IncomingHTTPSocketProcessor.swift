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
import Dispatch

import LoggerAPI
import Socket


/**
This class processes the data sent by the client after the data was read. The data is parsed, filling in a `HTTPServerRequest` object. When the parsing is complete, the `ServerDelegate` is invoked.
 
### Usage Example: ###
````swift
 //Create an `IncomingHTTPSocketProcessor` object.
 var processor : IncomingHTTPSocketProcessor?
 
 //Write from an NSMutableData buffer.
 processor.write(from: NSMutableData)
 
 //Write from a data object.
 processor.write(from: utf8, length: utf8Length)
 ````
 */
public class IncomingHTTPSocketProcessor: IncomingSocketProcessor {

    /**
     A back reference to the `IncomingSocketHandler` processing the socket that
     this `IncomingDataProcessor` is processing.
     
     ### Usage Example: ###
     ````swift
     processor?.handler = handler
     ````
     */
    public weak var handler: IncomingSocketHandler?
        
    private weak var delegate: ServerDelegate?
    
    /**
     Keep alive timeout for idle sockets in seconds
     
     ### Usage Example: ###
     ````swift
     print("timeout=\(Int(IncomingHTTPSocketProcessor.keepAliveTimeout))")
     ````
     */
    static let keepAliveTimeout: TimeInterval = 60
    
    /// A flag indicating that the client has requested that the socket be kept alive
    private var _clientRequestedKeepAlive = false
    private let cRKAQueue = DispatchQueue(label: "cRKAQueue", attributes: .concurrent)
    private(set) var clientRequestedKeepAlive: Bool {
        get {
            return cRKAQueue.sync {
                return _clientRequestedKeepAlive
            }
        }
        set {
            cRKAQueue.sync(flags: .barrier) {
                _clientRequestedKeepAlive = newValue
            }
        }
    }

    private var _keepAliveUntil: TimeInterval = 0.0
    private let kAUQueue = DispatchQueue(label: "kAUQueue", attributes: .concurrent)

    /**
     The socket if idle will be kep alive until...
     
     ### Usage Example: ###
     ````swift
     processor?.keepAliveUntil = 0.0
     ````
     */
    public var keepAliveUntil: TimeInterval {
        get {
            return kAUQueue.sync {
                return _keepAliveUntil
            }
        }
        set {
            kAUQueue.sync(flags: .barrier) {
                _keepAliveUntil = newValue
            }
        }
    }

    /// A flag indicating that the client has requested that the prtocol be upgraded
    private(set) var isUpgrade = false

    private var _inProgress: Bool = true
    private let inProgressQueue = DispatchQueue(label: "inProgressQueue", attributes: .concurrent)

    /**
     A flag that indicates that there is a request in progress
     
     ### Usage Example: ###
     ````swift
     processor?.inProgress = false
     ````
     */
    public var inProgress: Bool {
        get {
            return inProgressQueue.sync {
                return _inProgress
            }
        }
        set {
            inProgressQueue.sync(flags: .barrier) {
                _inProgress = newValue
            }
        }
    }
    
    ///HTTP Parser
    private let httpParser: HTTPParser
    
    /// Indicates whether the HTTP parser has encountered a parsing error
    private var parserErrored = false
    
    /// Controls the number of requests that may be sent on this connection.
    private(set) var keepAliveState: KeepAliveState
    
    /// Should this socket actually be kept alive?
    var isKeepAlive: Bool { return clientRequestedKeepAlive && keepAliveState.keepAlive() && !parserErrored }
    
    let socket: Socket
    
    /// An enum for internal state
    enum State {
        case reset, readingMessage, messageCompletelyRead
    }
    
    /// The state of this handler
    private var _state = State.readingMessage
    private let stateQueue = DispatchQueue(label: "stateQueue", attributes: .concurrent)
    private(set) var state: State {
        get {
            return stateQueue.sync {
                return _state
            }
        }
        set {
            stateQueue.sync(flags: .barrier) {
                _state = newValue
            }
        }
    }

    /// Location in the buffer to start parsing from
    private var parseStartingFrom = 0
    
    init(socket: Socket, using: ServerDelegate, keepalive: KeepAliveState) {
        delegate = using
        self.httpParser = HTTPParser(isRequest: true)
        self.socket = socket
        self.keepAliveState = keepalive
    }
    
    /**
     Process data read from the socket. It is either passed to the HTTP parser or
     it is saved in the Pseudo synchronous reader to be read later on.
     
     - Parameter buffer: An NSData object that contains the data read from the socket.
     
     - Returns: true if the data was processed, false if it needs to be processed later.
     
     ### Usage Example: ###
     ````swift
     let processed = processor.process(readBuffer)
     ````
     */
    public func process(_ buffer: NSData) -> Bool {
        let result: Bool
        
        switch(state) {
        case .reset:
            httpParser.reset()
            state = .readingMessage
            fallthrough

        case .readingMessage:
            inProgress = true
            parse(buffer)
            result = parseStartingFrom == 0
            
        case .messageCompletelyRead:
            result = parseStartingFrom == 0 && buffer.length == 0
            break
        }
        
        return result
    }
    
    /**
     Write data to the socket
     
     - Parameter data: An NSData object containing the bytes to be written to the socket.
     
     ### Usage Example: ###
     ````swift
     processor.write(from: buffer)
     ````
     */
    public func write(from data: NSData) {
        handler?.write(from: data)
    }
    
    /**
     Write a sequence of bytes in an array to the socket
     
     - Parameter from: An UnsafeRawPointer to the sequence of bytes to be written to the socket.
     - Parameter length: The number of bytes to write to the socket.
     
     ### Usage Example: ###
     ````swift
     processor.write(from: utf8, length: utf8Length)
     ````
     */
    public func write(from bytes: UnsafeRawPointer, length: Int) {
        handler?.write(from: bytes, length: length)
    }
    
    /**
     Close the socket and mark this handler as no longer in progress.
     
     ### Usage Example: ###
     ````swift
     processor?.close()
     ````
     */
    public func close() {
        keepAliveUntil=0.0
        inProgress = false
        clientRequestedKeepAlive = false
        handler?.prepareToClose()
    }
    
    /**
     Called by the `IncomingSocketHandler` to tell us that the socket has been closed
     by the remote side.
     
     ### Usage Example: ###
     ````swift
     processor?.socketClosed()
     ````
     */
    public func socketClosed() {
        keepAliveUntil=0.0
        inProgress = false
        clientRequestedKeepAlive = false
    }
    
    /// Parse the message
    ///
    /// - Parameter buffer: An NSData object contaning the data to be parsed
    /// - Parameter from: From where in the buffer to start parsing
    /// - Parameter completeBuffer: An indication that the complete buffer is being passed in.
    ///                            If true and the entire buffer is parsed, an EOF indication
    ///                            will be passed to the http_parser.
    func parse (_ buffer: NSData, from: Int, completeBuffer: Bool=false) -> HTTPParserStatus {
        var status = HTTPParserStatus()
        let length = buffer.length - from
        
        guard length > 0  else {
            /* Handle unexpected EOF. Usually just close the connection. */
            status.error = .unexpectedEOF
            return status
        }
                
        // If we were reset because of keep alive
        if  status.state == .reset  {
            return status
        }
        
        let bytes = buffer.bytes.assumingMemoryBound(to: Int8.self) + from
        let (numberParsed, upgrade) = httpParser.execute(bytes, length: length)
        
        if completeBuffer && numberParsed == length {
            // Tell parser we reached the end
            _ = httpParser.execute(bytes, length: 0)
        }
        
        if upgrade == 1 {
            status.upgrade = true
        }
        
        status.bytesLeft = length - numberParsed
        
        if httpParser.completed {
            status.state = .messageComplete
            status.keepAlive = httpParser.isKeepAlive() 
            return status
        }
        else if numberParsed != length  {
            /* Handle error. Usually just close the connection. */
            status.error = .parsedLessThanRead
        }
        
        return status
    }
    
    /// Invoke the HTTP parser against the specified buffer of data and
    /// convert the HTTP parser's status to our own.
    private func parse(_ buffer: NSData) {
        let parsingStatus = parse(buffer, from: parseStartingFrom)
        
        if parsingStatus.bytesLeft == 0 {
            parseStartingFrom = 0
        }
        else {
            parseStartingFrom = buffer.length - parsingStatus.bytesLeft
        }
        
        guard  parsingStatus.error == nil  else  {
            Log.error("Failed to parse a request. \(parsingStatus.error!)")
            let response = HTTPServerResponse(processor: self, request: nil)
            response.statusCode = .badRequest
            // We must avoid any further attempts to process data from this client
            // after a parser error has occurred. (see Kitura-net#228)
            parserErrored = true
            do {
                try response.end()
            }
            catch {}

            return
        }
        
        switch(parsingStatus.state) {
        case .initial:
            break
        case .messageComplete:
            isUpgrade = parsingStatus.upgrade
            clientRequestedKeepAlive = parsingStatus.keepAlive && !isUpgrade
            parsingComplete()
        case .reset:
            state = .reset
            break
        }
    }
    
    /// Parsing has completed. Invoke the ServerDelegate to handle the request
    private func parsingComplete() {
        state = .messageCompletelyRead
        
        let request = HTTPServerRequest(socket: socket, httpParser: httpParser)
        request.parsingCompleted()
        
        let response = HTTPServerResponse(processor: self, request: request)

        // If the IncomingSocketHandler was freed, we can't handle the request
        guard let handler = handler else {
            Log.error("IncomingSocketHandler not set or freed before parsing complete")
            return
        }
        
        if isUpgrade {
            ConnectionUpgrader.instance.upgradeConnection(handler: handler, request: request, response: response)
            inProgress = false
        }
        else {
            weak var weakRequest = request
            DispatchQueue.global().async() { [weak self] in
                if let strongSelf = self, let strongRequest = weakRequest {
                    Monitor.delegate?.started(request: strongRequest, response: response)
                    strongSelf.delegate?.handle(request: strongRequest, response: response)
                }
            }
        }
    }
    
    /// A socket can be kept alive for future requests. Set it up for future requests and mark how long it can be idle.
    func keepAlive() {
        state = .reset
        keepAliveState.decrement()
        inProgress = false
        keepAliveUntil = Date(timeIntervalSinceNow: IncomingHTTPSocketProcessor.keepAliveTimeout).timeIntervalSinceReferenceDate
        handler?.handleBufferedReadData()
    }
}

class HTTPIncomingSocketProcessorCreator: IncomingSocketProcessorCreator {
    public let name = "http/1.1"
    
    public func createIncomingSocketProcessor(socket: Socket, using: ServerDelegate) -> IncomingSocketProcessor {
        return IncomingHTTPSocketProcessor(socket: socket, using: using, keepalive: .unlimited)
    }
    
    /// Create an instance of `IncomingHTTPSocketProcessor` for use with new incoming sockets.
    ///
    /// - Parameter socket: The new incoming socket.
    /// - Parameter using: The `ServerDelegate` the HTTPServer is working with, which should be used
    ///                   by the created `IncomingSocketProcessor`, if it works with `ServerDelegate`s.
    /// - Parameter keepalive: The `KeepAliveState` for this connection (limited, unlimited or disabled)
    func createIncomingSocketProcessor(socket: Socket, using: ServerDelegate, keepalive: KeepAliveState) -> IncomingSocketProcessor {
        return IncomingHTTPSocketProcessor(socket: socket, using: using, keepalive: keepalive)
    }
}
