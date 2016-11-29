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

/// This class processes the data sent by the client after the data was read. The data
/// is parsed, filling in a `HTTPServerRequest` object. When the parsing is complete, the
/// `ServerDelegate` is invoked.
public class IncomingHTTPSocketProcessor: IncomingSocketProcessor {
    
    /// A back reference to the `IncomingSocketHandler` processing the socket that
    /// this `IncomingDataProcessor` is processing.
    public weak var handler: IncomingSocketHandler?
        
    private weak var delegate: ServerDelegate?
    
    let request: HTTPServerRequest
    
    /// The `ServerResponse` object used to enable the `ServerDelegate` to respond to the incoming request
    /// - Note: This var is optional to enable it to be constructed in the init function
    private var response: ServerResponse!
    
    /// Keep alive timeout for idle sockets in seconds
    static let keepAliveTimeout: TimeInterval = 60
    
    /// A flag indicating that the client has requested that the socket be kept alive
    private(set) var clientRequestedKeepAlive = false
    
    /// The socket if idle will be kep alive until...
    public var keepAliveUntil: TimeInterval = 0.0
    
    /// A flag indicating that the client has requested that the prtocol be upgraded
    private(set) var isUpgrade = false
    
    /// A flag that indicates that there is a request in progress
    public var inProgress = true
    
    /// The number of remaining requests that will be allowed on the socket being handled by this handler
    private(set) var numberOfRequests = 100
    
    /// Should this socket actually be kept alive?
    var isKeepAlive: Bool { return clientRequestedKeepAlive && numberOfRequests > 0 }
    
    /// An enum for internal state
    enum State {
        case reset, initial, messageCompletelyRead
    }
    
    /// The state of this handler
    private(set) var state = State.initial
    
    init(socket: Socket, using: ServerDelegate) {
        delegate = using
        request = HTTPServerRequest(socket: socket)
        
        response = HTTPServerResponse(processor: self)
    }
    
    /// Process data read from the socket. It is either passed to the HTTP parser or
    /// it is saved in the Pseudo synchronous reader to be read later on.
    ///
    /// - Parameter buffer: An NSData object that contains the data read from the socket.
    ///
    /// - Returns: true if the data was processed, false if it needs to be processed later.
    public func process(_ buffer: NSData) -> Bool {
        let result: Bool
        switch(state) {
        case .reset:
            request.prepareToReset()
            state = .initial
            fallthrough
            
        case .initial:
            inProgress = true
            parse(buffer)
            result = true
            
        case .messageCompletelyRead:
            result = false
        }
        return result
    }
    
    /// Write data to the socket
    ///
    /// - Parameter data: An NSData object containing the bytes to be written to the socket.
    public func write(from data: NSData) {
        handler?.write(from: data)
    }
    
    /// Write a sequence of bytes in an array to the socket
    ///
    /// - Parameter from: An UnsafeRawPointer to the sequence of bytes to be written to the socket.
    /// - Parameter length: The number of bytes to write to the socket.
    public func write(from bytes: UnsafeRawPointer, length: Int) {
        handler?.write(from: bytes, length: length)
    }
    
    /// Close the socket and mark this handler as no longer in progress.
    public func close() {
        handler?.prepareToClose()
        request.release()
    }
    
    /// Called by the `IncomingSocketHandler` to tell us that the socket has been closed
    /// by the remote side. This is ignored at this time.
    public func socketClosed() {}
    
    /// Invoke the HTTP parser against the specified buffer of data and
    /// convert the HTTP parser's status to our own.
    private func parse(_ buffer: NSData) {
        let parsingStatus = request.parse(buffer)
        guard  parsingStatus.error == nil  else  {
            Log.error("Failed to parse a request. \(parsingStatus.error!)")
            if  let response = response {
                response.statusCode = .badRequest
                do {
                    try response.end()
                }
                catch {}
            }
            return
        }
        
        switch(parsingStatus.state) {
        case .initial:
            break
        case .messageComplete:
            isUpgrade = parsingStatus.upgrade
            clientRequestedKeepAlive = parsingStatus.keepAlive && !isUpgrade
            parsingComplete()
        case .reset, .headersComplete:
            break
        }
    }
    
    /// Parsing has completed. Invoke the ServerDelegate to handle the request
    private func parsingComplete() {
        state = .messageCompletelyRead
        response.reset()
        
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
            DispatchQueue.global().async() { [unowned self] in
                Monitor.delegate?.started(request: self.request, response: self.response)
                self.delegate?.handle(request: self.request, response: self.response)
            }
        }
    }
    
    /// A socket can be kept alive for future requests. Set it up for future requests and mark how long it can be idle.
    func keepAlive() {
        state = .reset
        numberOfRequests -= 1
        inProgress = false
        keepAliveUntil = Date(timeIntervalSinceNow: IncomingHTTPSocketProcessor.keepAliveTimeout).timeIntervalSinceReferenceDate
        handler?.handleBufferedReadData()
    }
}
