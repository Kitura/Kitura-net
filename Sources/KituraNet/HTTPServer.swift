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
import LoggerAPI
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
    public weak var delegate: ServerDelegate?
    
    /// 
    /// Port number for listening for new connections
    ///
    public private(set) var port: Int?
    
    /// 
    /// TCP socket used for listening for new connections
    ///
    private var listenSocket: Socket?
    
    ///
    /// Whether the HTTP server has stopped listening
    ///
    var stopped = false

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
			self.listen(socket: self.listenSocket, port: self.port!)
		}
		
        ListenerGroup.enqueueAsynchronously(on: HTTPServer.listenerQueue, block: queuedBlock)
        
    }

    ///
    /// Stop listening for new connections
    ///
    public func stop() {
        if let listenSocket = listenSocket {
            stopped = true
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
    public static func listen(port: Int, delegate: ServerDelegate, notOnMainQueue: Bool=false) -> HTTPServer {
        
        let server = HTTP.createServer()
        server.delegate = delegate
        server.listen(port: port, notOnMainQueue: notOnMainQueue)
        return server
        
    }
    
    ///
    /// Handles instructions for listening on a socket
    ///
    /// - Parameter socket: socket to use for connecting
    /// - Parameter port: number to listen on
    ///
    func listen(socket: Socket?, port: Int) {
        
        do {
            guard let socket = socket else {
                return
            }
            
            try socket.listen(on: port)
            Log.info("Listening on port \(port)")
            
            // TODO: Change server exit to not rely on error being thrown
            repeat {
                let clientSocket = try socket.acceptClientConnection()
                Log.info("Accepted connection from: " +
                    "\(clientSocket.remoteHostname):\(clientSocket.remotePort)")
                handleClientRequest(socket: clientSocket)
            } while true
        } catch let error as Socket.Error {
            
            if stopped && error.errorCode == Int32(Socket.SOCKET_ERR_ACCEPT_FAILED) {
                Log.info("Server has stopped listening")
            }
            else {
                Log.error("Error reported:\n \(error.description)")
            }
        } catch {
            Log.error("Unexpected error...")
        }
    }
    
    ///
    /// Handle a new client HTTP request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    ///
    func handleClientRequest(socket clientSocket: Socket, fromKeepAlive: Bool=false) {

        guard let delegate = delegate else {
            return
        }
        
        HTTPServer.clientHandlerQueue.enqueueAsynchronously() {

            let request = HTTPServerRequest(socket: clientSocket)
            let response = HTTPServerResponse(socket: clientSocket, request: request)
            request.parse() { status in
                switch status {
                case .success:
                    delegate.handle(request: request, response: response)
                case .parsedLessThanRead:
                    response.statusCode = .badRequest
                    do {
                        try response.end()
                    }
                    catch {
                        // handle error in connection
                    }
                case .unexpectedEOF:
                    break
                case .internalError:
                    break
                }
            }

        }
    }
    
    ///
    /// Wait for all of the listeners to stop
    ///
    /// TODO: Note that this calls the ListenerGroup object, and is left in for
    /// backwards compability reasons. Can be safely removed once IBM-Swift/Kitura/Kitura.swift 
    /// is patched to directly talk to ListenerGroup.
    ///
    public static func waitForListeners() {
        ListenerGroup.waitForListeners()
    }
}
