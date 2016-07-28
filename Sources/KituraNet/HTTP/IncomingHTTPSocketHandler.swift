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

#if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
    import Dispatch
#endif

import Foundation

import LoggerAPI
import Socket

/// This class handles incoming sockets to the HTTPServer. The data sent by the client
/// is read and parsed filling in a ServerRequest object. When parsing is complete the
/// ServerDelegate is invoked.
///
/// **Note:** This class uses different underlying technologies depending on:
///     1. On Linux if no special compile time options are specified, epoll is used
///     2. On OSX DispatchSource is used
///     3. On Linux if the compile time option -Xswiftc -DGCD_ASYNCH is specified,
///        DispatchSource is used, as it is used on OSX.
class IncomingHTTPSocketHandler: IncomingSocketHandler {
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
        typealias DateType = Date
        typealias TimeIntervalType = TimeInterval
    
        typealias DispatchSourceReadType = DispatchSourceRead
        static let socketReaderQueue = DispatchQueue(label: "Socket Reader", attributes: DispatchQueueAttributes.serial)
    #else
        typealias DateType = NSDate
        typealias TimeIntervalType = NSTimeInterval
    
        #if GCD_ASYNCH
            typealias DispatchSourceReadType = dispatch_source_t
            static let socketReaderQueue = dispatch_queue_create("Socket Reader", DISPATCH_QUEUE_SERIAL)
        #endif
    #endif
    
    
    #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS) || GCD_ASYNCH
        // Note: This var is optional to enable it to be constructed in the init function
        var source: DispatchSourceReadType!
    #endif

    let socket: Socket
        
    private weak var delegate: ServerDelegate?
    
    /// The file descriptor of the incoming socket
    var fileDescriptor: Int32 { return socket.socketfd }
        
    private let reader: PseudoSynchronousReader
    
    
    private let request: HTTPServerRequest
    
    /// The ServerResponse object used to enable the ServerDelegate to respond to the incoming request
    /// Note: This var is optional to enable it to be constructed in the init function
    private var response: ServerResponse!
    
    /// Keep alive timeout for idle sockets in seconds
    static let keepAliveTimeout: TimeIntervalType = 60
    
    /// A flag indicating that the client has requested that the socket be kep alive
    private(set) var clientRequestedKeepAlive = false
    
    /// The socket if idle will be kep alive until...
    var keepAliveUntil: TimeIntervalType = 0.0
    
    /// A flag to indicate that the socket has a request in progress
    var inProgress = true
    
    /// Number of remaining requests that will be allowed on the socket being handled by this handler
    private(set) var numberOfRequests = 20
    
    /// Should this socket actually be kep alive?
    var isKeepAlive: Bool { return clientRequestedKeepAlive && numberOfRequests > 0 }
    
    /// An enum for internal state
    enum State {
        case reset, initial, parsedHeaders
    }
    
    /// The state of this handler
    private(set) var state = State.initial
    
    init(socket: Socket, using: ServerDelegate) {
        self.socket = socket
        delegate = using
        reader = PseudoSynchronousReader(clientSocket: socket)
        request = HTTPServerRequest(reader: reader)
        
        response = HTTPServerResponse(handler: self)
        
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
            source = DispatchSource.read(fileDescriptor: socket.socketfd,
		                         queue: IncomingHTTPSocketHandler.socketReaderQueue)
        
            source.setEventHandler() {
                self.handleRead()
            }
            source.setCancelHandler() {
                self.dispatchSourceCancelHandler()
            }
            source.resume()
	#elseif GCD_ASYNCH
            source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(socket.socketfd), 0, 
		                            IncomingHTTPSocketHandler.socketReaderQueue)

            dispatch_source_set_event_handler(source) {
                self.handleRead()
            }
            dispatch_source_set_cancel_handler(source) {
                self.dispatchSourceCancelHandler()
            }
            dispatch_resume(source)
        #endif
    }
    
    /// Read in the available data and hand off to common processing code
    func handleRead() {
        let buffer = NSMutableData()
        
        do {
            var length = 1
            while  length > 0  {
                length = try socket.read(into: buffer)
            }
            if  buffer.length > 0  {
                process(buffer)
            }
            else {
                if  errno != EAGAIN  &&  errno != EWOULDBLOCK  {
                    close()
                }
            }
        }
        catch let error as Socket.Error {
            Log.error(error.description)
        } catch {
            Log.error("Unexpected error...")
        }
    }
    
    /// Write data to the socket
    func write(from data: NSData) {
        guard socket.socketfd > -1  else { return }
        
        do {
            try socket.write(from: data)
        }
        catch {
            Log.error("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(errorString(error: errno)).")
        }
    }
    
    /// Close the socket and mark this handler as no longer in progress.
    ///
    /// **Note:** On Linux closing the socket causes it to be dropped by epoll.
    /// **Note:** On OSX the cancel handler will actually close the socket.
    func close() {
        #if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)
            source.cancel()
        #elseif GCD_ASYNCH
	    dispatch_source_cancel(source!)
        #else
            dispatchSourceCancelHandler()
        #endif
    }
    
    /// DispatchSource cancel handler
    private func dispatchSourceCancelHandler() {
        if  socket.socketfd > -1 {
            socket.close()
        }
        inProgress = false
        keepAliveUntil = 0.0
    }
    
    /// Process data read from the socket. It is either passed to the HTTP parser or
    /// it is saved in the Pseudo synchronous reader to be read later on.
    func process(_ buffer: NSData) {
        switch(state) {
        case .reset:
            request.reset()
            response.reset()
            fallthrough
            
        case .initial:
            inProgress = true
            HTTPServer.clientHandlerQueue.enqueueAsynchronously() { [unowned self] in
                self.parse(buffer)
            }
            
        case .parsedHeaders:
            reader.addDataToRead(from: buffer)
        }
    }
    
    /// Invoke the HTTP parser against the specified buffer of data and
    /// convert the HTTP parser's status to our own.
    private func parse(_ buffer: NSData) {
        let parsingStatus = request.parse(buffer)
        guard  parsingStatus.error == nil  else  {
            Log.error("Failed to parse a request")
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
        keepAliveUntil = NSDate(timeIntervalSinceNow: IncomingHTTPSocketHandler.keepAliveTimeout).timeIntervalSinceReferenceDate
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
