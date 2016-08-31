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
import Socket

/// This class processes the data sent by the client after the data was read. It
/// is parsed filling in a ServerRequest object. When parsing is complete the
/// ServerDelegate is invoked.
public class IncomingHTTPSocketProcessor: IncomingSocketProcessor {
    
    public weak var handler: IncomingSocketHandler?
        
    private weak var delegate: ServerDelegate?
    
    private let reader: PseudoSynchronousReader
    
    private let request: HTTPServerRequest
    
    /// The ServerResponse object used to enable the ServerDelegate to respond to the incoming request
    /// Note: This var is optional to enable it to be constructed in the init function
    private var response: ServerResponse!
    
    /// Keep alive timeout for idle sockets in seconds
    static let keepAliveTimeout: TimeInterval = 60
    
    /// A flag indicating that the client has requested that the socket be kep alive
    private(set) var clientRequestedKeepAlive = false
    
    /// The socket if idle will be kep alive until...
    public var keepAliveUntil: TimeInterval = 0.0
    
    /// A flag to indicate that the socket has a request in progress
    public var inProgress = true
    
    /// Number of remaining requests that will be allowed on the socket being handled by this handler
    private(set) var numberOfRequests = 100
    
    /// Should this socket actually be kep alive?
    var isKeepAlive: Bool { return clientRequestedKeepAlive && numberOfRequests > 0 }
    
    /// An enum for internal state
    enum State {
        case reset, initial, parsedHeaders
    }
    
    /// The state of this handler
    private(set) var state = State.initial
    
    init(socket: Socket, using: ServerDelegate) {
        delegate = using
        reader = PseudoSynchronousReader(clientSocket: socket)
        request = HTTPServerRequest(reader: reader)
        
        response = HTTPServerResponse(processor: self)
    }
    
    /// Process data read from the socket. It is either passed to the HTTP parser or
    /// it is saved in the Pseudo synchronous reader to be read later on.
    public func process(_ buffer: Data) {
        switch(state) {
        case .reset:
            request.prepareToReset()
            response.reset()
            fallthrough
            
        case .initial:
            inProgress = true
            HTTPServer.clientHandlerQueue.async() { [unowned self] in
                self.parse(buffer)
            }
            
        case .parsedHeaders:
            reader.addDataToRead(from: buffer)
        }
    }
    
    /// Write data to the socket
    public func write(from data: Data) {
        handler?.write(from: data)
    }
    
    /// Close the socket and mark this handler as no longer in progress.
    public func close() {
        handler?.prepareToClose()
        request.close()
    }
    
    /// Invoke the HTTP parser against the specified buffer of data and
    /// convert the HTTP parser's status to our own.
    private func parse(_ buffer: Data) {
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
        case .headersComplete, .messageComplete:
            clientRequestedKeepAlive = parsingStatus.keepAlive
            parsingComplete()
        case .reset:
            break
        }
    }
    
    /// Parsing has completed enough to invoke the ServerDelegate to handle the request
    private func parsingComplete() {
        state = .parsedHeaders
        delegate?.handle(request: request, response: response)
    }
    
    /// A socket can be kept alive for future requests. Set it up for future requests and mark how long it can be idle.
    func keepAlive() {
        state = .reset
        numberOfRequests -= 1
        inProgress = false
        keepAliveUntil = Date(timeIntervalSinceNow: IncomingHTTPSocketProcessor.keepAliveTimeout).timeIntervalSinceReferenceDate
    }
    
    /// Drain the socket of the data of the current request.
    func drain() {
        request.drain()
    }
    
    /// Private method to return a string representation on a value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    func errorString(error: Int32) -> String {
        
        return String(validatingUTF8: strerror(error)) ?? "Error: \(error)"
    }
}
