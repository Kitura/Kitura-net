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

// MARK: HttpServer

public class HttpServer {

    ///
    /// Queue for listening and establishing new connections
    ///
    private static var listenerQueue = Queue(type: .PARALLEL, label: "HttpServer.listenerQueue")

    ///
    /// Queue for handling client requests
    ///
    private static var clientHandlerQueue = Queue(type: .PARALLEL, label: "HttpServer.clientHandlerQueue")

    ///
    /// HttpServerDelegate
    ///
    public weak var delegate: HttpServerDelegate?
    
    ///
    /// Http service provider interface
    ///
    private let spi: HttpServerSpi
    
    /// 
    /// Port number for listening for new connections
    ///
    private var _port: Int?
    public var port: Int? {
        get { return _port }
    }
    
    /// 
    /// TCP socket used for listening for new connections
    ///
    private var listenSocket: Socket?
    
    ///
    /// Initializes an HttpServer instance
    ///
    /// - Returns: an HttpServer instance
    ///
    public init() {
        
        spi = HttpServerSpi()
        spi.delegate = self
        
    }

    ///
    /// Listens for connections on a socket
    ///
    /// - Parameter port: port number for new connections (ex. 8090)
    /// - Parameter notOnMainQueue: whether to have the listener run on the main queue 
    ///
    public func listen(port: Int, notOnMainQueue: Bool=false) {
        
        self._port = port
		
		do {
            
			self.listenSocket = try Socket.makeDefault()
            
		} catch let error as Socket.Error {
			print("Error reported:\n \(error.description)")
		} catch {
            print("Unexpected error...")
		}

		let queuedBlock = {
			self.spi.spiListen(socket: self.listenSocket, port: self._port!)
		}
		
		if notOnMainQueue {
			HttpServer.listenerQueue.queueAsync(queuedBlock)
		}
		else {
			Queue.queueIfFirstOnMain(queue: HttpServer.listenerQueue, block: queuedBlock)
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
    /// Static method to create a new HttpServer and have it listen for conenctions
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for Http connections
    /// - Parameter notOnMainQueue: whether to listen for new connections on the main Queue
    ///
    /// - Returns: a new HttpServer instance
    ///
    public static func listen(port: Int, delegate: HttpServerDelegate, notOnMainQueue: Bool=false) -> HttpServer {
        
        let server = Http.createServer()
        server.delegate = delegate
        server.listen(port: port, notOnMainQueue: notOnMainQueue)
        return server
        
    }
    
}

// MARK: HttpServerSpiDelegate extension
extension HttpServer : HttpServerSpiDelegate {

    ///
    /// Handle a new client Http request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    ///
    func handleClientRequest(socket clientSocket: Socket) {

        guard let delegate = delegate else {
            return
        }
        
        HttpServer.clientHandlerQueue.queueAsync() {

            let response = ServerResponse(socket: clientSocket)
            let request = ServerRequest(socket: clientSocket)
            request.parse() { status in
                switch status {
                case .Success:
                    delegate.handle(request: request, response: response)
                case .ParsedLessThanRead:
                    print("ParsedLessThanRead")
                    response.statusCode = .BAD_REQUEST
                    do {
                        try response.end()
                    }
                    catch {
                        // handle error in connection
                    }
                case .UnexpectedEOF:
                    print("UnexpectedEOF")
                case .InternalError:
                    print("InternalError")
                }
            }

        }
    }
}

///
/// Delegate protocol for an HttpServer
///
public protocol HttpServerDelegate: class {

    func handle(request: ServerRequest, response: ServerResponse)
    
}
