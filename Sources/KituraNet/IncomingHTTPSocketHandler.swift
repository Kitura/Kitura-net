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

import Dispatch
import Foundation


import LoggerAPI
import Socket

class IncomingHTTPSocketHandler: IncomingSocketHandler {
    
    // Note: This var is optional to enable it to be constructed in the init function
    private var channel: dispatch_io_t?
    
    private let socket: Socket
    
    private weak var delegate: ServerDelegate?
    
    ///
    /// The file descriptor of the incoming socket
    ///
    var fileDescriptor: Int32 { return socket.socketfd }
    
    private let reader: PseudoAsynchronousReader
    
    private let request: HTTPServerRequest
    
    // Note: This var is optional to enable it to be constructed in the init function
    private var response: ServerResponse?
    
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
        
        channel = dispatch_io_create(DISPATCH_IO_STREAM, socket.socketfd, HTTPServer.clientHandlerQueue.osQueue) { error in
            self.socket.close()
        }
        dispatch_io_set_low_water(channel!, 1)
        
        response = HTTPServerResponse(handler: self)
        
        dispatch_io_read(channel!, 0, Int.max, HTTPServer.clientHandlerQueue.osQueue) {done, data, error in
            self.handleRead(done: done, data: data, error: error)
        }
    }
    
    private func handleRead(done: Bool, data: dispatch_data_t?, error: Int32) {
        guard !done else {
            if error != 0 {
                Log.error("Error reading from \(socket.socketfd)")
                print("Error reading from \(socket.socketfd)")
            }
            close()
            return
        }
        
        guard let data = data else { return }
        
        let buffer = NSMutableData()
        dispatch_data_apply(data) { (region, offset, dataBuffer, size) -> Bool in
            guard let dataBuffer = dataBuffer else { return true }
            buffer.append(dataBuffer, length: size)
            return true
        }
        
        switch(state) {
        case .reset:
            request.reset()
            response!.reset()
            fallthrough
            
        case .initial:
            parse(buffer)
            
        case .parsed:
            reader.addToAvailableData(from: buffer)
            break
        }
    }
    
    private func parse(_ buffer: NSData) {
        let (parsingState, _ ) = request.parse(buffer)
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
    func write(from: NSData) {
        let temp = dispatch_data_create( from.bytes, from.length, HTTPServer.clientHandlerQueue.osQueue, nil)
        #if os(Linux)
            let data = temp
        #else
            guard let data = temp  else { return }
        #endif
        dispatch_io_write(channel!, 0, data, HTTPServer.clientHandlerQueue.osQueue) { _,_,_ in }
    }
    
    ///
    /// Close the socket
    ///
    func close() {
        dispatch_io_close(channel!, 0)
    }
    
    ///
    /// Private method to return a string representation on a value of errno.
    ///
    /// - Returns: String containing relevant text about the error.
    ///
    private func errorString(error: Int32) -> String {
        
        return String(validatingUTF8: strerror(error)) ?? "Error: \(error)"
    }
}

