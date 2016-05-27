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

// MARK: HTTPServer

public class HTTPServer {

    ///
    /// Queue for listening and establishing new connections
    ///
    private static var listenerQueue = Queue(type: .parallel, label: "HTTPServer.listenerQueue")

    ///
    /// Queue for handling client requests
    ///
    private static var clientHandlerQueue = Queue(type: .parallel, label: "HTTPServer.clientHandlerQueue")

    ///
    /// HTTPServerDelegate
    ///
    public weak var delegate: HTTPServerDelegate?
    
    ///
    /// HTTP service provider interface
    ///
    private let spi: HTTPServerSPI
    
    /// 
    /// Port number for listening for new connections
    ///
    public private(set) var port: Int?
    
    /// 
    /// TCP socket used for listening for new connections
    ///
    private var listenSocket: Socket?
    
    ///
    /// Initializes an HTTPServer instance
    ///
    /// - Returns: an HTTPServer instance
    ///
    public init() {
        
        spi = HTTPServerSPI()
        spi.delegate = self
        
    }

    ///
    /// Listens for connections on a socket
    ///
    /// - Parameter port: port number for new connections (ex. 8090)
    /// - Parameter notOnMainQueue: whether to have the listener run on the main queue 
    ///
    public func listen(port: Int, notOnMainQueue: Bool=false) {
        
        self.port = port
		
		do {
            
			self.listenSocket = try Socket.create()
            
		} catch let error as Socket.Error {
			print("Error reported:\n \(error.description)")
		} catch {
            print("Unexpected error...")
		}

		let queuedBlock = {
			self.spi.spiListen(socket: self.listenSocket, port: self.port!)
		}
		
		if notOnMainQueue {
			HTTPServer.listenerQueue.enqueueAsynchronously(queuedBlock)
		}
		else {
			Queue.enqueueIfFirstOnMain(queue: HTTPServer.listenerQueue, block: queuedBlock)
		}
        
    }

    ///
    /// Stop listening for new connections
    ///
    public func stop() {
        
        if let listenSocket = listenSocket {
            spi.stopped = true
            listenSocket.close()
        }
        
    }

    ///
    /// Static method to create a new HTTPServer and have it listen for conenctions
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for HTTP connections
    /// - Parameter notOnMainQueue: whether to listen for new connections on the main Queue
    ///
    /// - Returns: a new HTTPServer instance
    ///
    public static func listen(port: Int, delegate: HTTPServerDelegate, notOnMainQueue: Bool=false) -> HTTPServer {
        
        let server = HTTP.createServer()
        server.delegate = delegate
        server.listen(port: port, notOnMainQueue: notOnMainQueue)
        return server
        
    }
    
}

// MARK: HTTPServerSPIDelegate extension
extension HTTPServer : HTTPServerSPIDelegate {

    ///
    /// Handle a new client HTTP request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    ///
    func handleClientRequest(socket clientSocket: Socket, fromKeepAlive: Bool) {

        guard let delegate = delegate else {
            return
        }
        
        HTTPServer.clientHandlerQueue.enqueueAsynchronously() {

            let request = ServerRequest(socket: clientSocket)
            let response = ServerResponse(socket: clientSocket, request: request)
            request.parse() { status in
                switch status {
                case .success:
                    delegate.handle(request: request, response: response)
                case .parsedLessThanRead:
                    print("ParsedLessThanRead")
                    response.statusCode = .badRequest
                    do {
                        try response.end()
                    }
                    catch {
                        // handle error in connection
                    }
                case .unexpectedEOF:
                    print("UnexpectedEOF")
                case .internalError:
                    print("InternalError")
                }
            }

        }
    }
}

///
/// Delegate protocol for an HTTPServer
///
public protocol HTTPServerDelegate: class {

    func handle(request: ServerRequest, response: ServerResponse)
    
}
