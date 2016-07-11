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

#if os(Linux)

import Foundation
import Glibc

    
import LoggerAPI
import Socket
    
class IncomingHTTPSocketHandler: IncomingSocketHandler {
    
    private let socket: Socket
    
    private weak var delegate: ServerDelegate?
    
    ///
    /// The file descriptor of the incoming socket
    ///
    var fileDescriptor: Int32 { return socket.socketfd }
    
    private let reader: PseudoAsynchronousReader
    
    private let request: HTTPServerRequest
    
    // Note: This var is optional to enable it to be constructed in the init function
    private var response: HTTPServerResponse?
    
    ///
    /// Keep alive timeout in seconds
    ///
    static let keepAliveTimeout: NSTimeInterval = 60
    
    private(set) var clientRequestedKeepAlive = false
    
    private(set) var numberOfRequests = 20
    
    var isKeepAlive: Bool { return clientRequestedKeepAlive && numberOfRequests > 0 }
    
    enum State {
        case reset, initial, parsed
    }
    
    private(set) var state = State.initial
    
    init(socket: Socket, using: ServerDelegate) {
        self.socket = socket
        delegate = using
        reader = PseudoAsynchronousReader(clientSocket: socket)
        request = HTTPServerRequest(reader: reader)
        response = HTTPServerResponse(handler: self)
    }
    
    func process() {
        switch(state) {
            case .reset:
                request.reset()
                response!.reset()
                fallthrough
            case .initial:
                processInitialState()
            
            case .parsed:
                readAvailableData()
                break
        }
    }
    
    private func processInitialState() {
        let buffer = NSMutableData()
        
        do {
            var length = 1
            while  length > 0  {
                length = try socket.read(into: buffer)
            }
            if  buffer.length > 0  {
                HTTPServer.clientHandlerQueue.enqueueAsynchronously() { [unowned self] in
                    self.parse(buffer)
                }
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
    
    private func parse(_ buffer: NSData) {
        let (parsingState, _) = request.parse(buffer)
        switch(parsingState) {
            case .error:
                break
            case .initial:
                break
            case .headersComplete, .messageComplete:
                clientRequestedKeepAlive = false
                parsingComplete()
            case .headersCompleteKeepAlive, .messageCompleteKeepAlive:
                clientRequestedKeepAlive = true
                parsingComplete()
            case .reset:
                break
        }
    }
    
    private func parsingComplete() {
        state = .parsed
        delegate?.handle(request: request, response: response!)
    }
    
    func readAvailableData() {
        let buffer = NSMutableData()
        
        do {
            var length = 1
            while  length > 0  {
                length = try socket.read(into: buffer)
            }
            if  buffer.length != 0  {
                reader.addToAvailableData(from: buffer)
            }
            else {
                close()
            }
        }
        catch let error as Socket.Error {
            Log.error(error.description)
        } catch {
            Log.error("Unexpected error...")
        }
        
        return
    }

    
    func keepAlive() {
        state = .reset
        numberOfRequests -= 1
    }
    
    func drain() {
        request.drain()
    }
    
    ///
    /// Write data to the socket
    ///
    func write(from data: NSData) {
        guard socket.socketfd > -1  else { return }
        
        do {
            try socket.write(from: data)
        }
        catch {
            print("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(lastError()).")
            Log.error("Write to socket (file descriptor \(socket.socketfd) failed. Error number=\(errno). Message=\(lastError()).")
        }
    }
    
    func close() {
        if  socket.socketfd > -1 {
            socket.close()
        }
    }
    
    ///
    /// Private method to return the last error based on the value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    ///
    private func lastError() -> String {
        
        return String(validatingUTF8: strerror(errno)) ?? "Error: \(errno)"
    }
}

    
#endif
