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

import Dispatch

import LoggerAPI
import Socket
import SSLService

// MARK: HTTPServer

/// An HTTP server that listens for connections on a socket.
public class HTTPServer {

    ///
    /// HTTPServerDelegate
    ///
    public weak var delegate: ServerDelegate?
    
    ///
    /// SSL cert configs for handling client requests
    ///
    public var sslConfig: SSLService.Configuration?
    
    /// Port number for listening for new connections.
    public private(set) var port: Int?
    
    /// TCP socket used for listening for new connections
    private var listenSocket: Socket?
    
    /// Whether the HTTP server has stopped listening
    var stopped = false
    
    /// Incoming socket handler
    private let socketManager = IncomingSocketManager()
    
    /// Maximum number of pending connections
    private let maxPendingConnections = 100

    
    /// Listen for connections on a socket.
    ///
    /// Listens for connections on a socket
    ///
    /// - Parameter port: port number for new connections (eg. 8090)
    /// - Parameter errorHandler: optional callback for error handling
    public func listen(port: Int, errorHandler: ((Swift.Error) -> Void)? = nil) {
        self.port = port

		do {
			self.listenSocket = try Socket.create()

            // If SSL config has been created, 
            // create and attach the SSLService delegate to the socket
            if let sslConfig = sslConfig {
               self.listenSocket?.delegate = try SSLService(usingConfiguration: sslConfig);
            }
            
        } catch let error {
            
            if error is Socket.Error {
                let socketError = error as! Socket.Error
                Log.error("Error reported:\n \(socketError.description)")
                
            } else if error is SSLError {
                // we have to catch SSLErrors separately since we are calling SSLService.Configuration
                let sslError = error as! SSLError
                Log.error("Error reported:\n \(sslError.description)")
                
            } else {
                Log.error("Unexpected error reported...")
            }
        }

        guard let socket = self.listenSocket else {
        // already did a callback on the error handler or logged error
        return
        }

        let queuedBlock = DispatchWorkItem(block: {
            do {
                try self.listen(socket: socket, port: port)
            } catch {
                if let callback = errorHandler {
                    callback(error)
                } else {
                    Log.error("Error listening on socket: \(error)")
                }
            }
        })

        ListenerGroup.enqueueAsynchronously(on: DispatchQueue.global(), block: queuedBlock)
    }

    /// Stop listening for new connections.
    public func stop() {
        if let listenSocket = listenSocket {
            stopped = true
            listenSocket.close()
        }
    }

    /// Static method to create a new HTTPServer and have it listen for connections.
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for HTTP connections
    /// - Parameter errorHandler: optional callback for error handling
    ///
    /// - Returns: a new `HTTPServer` instance
    public static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)? = nil) -> HTTPServer {
        let server = HTTP.createServer()
        server.delegate = delegate
        server.listen(port: port, errorHandler: errorHandler)
        return server
    }
    
    /// Handle instructions for listening on a socket
    ///
    /// - Parameter socket: socket to use for connecting
    /// - Parameter port: number to listen on
    func listen(socket: Socket, port: Int) throws {
        do {
            try socket.listen(on: port, maxBacklogSize: maxPendingConnections)
            Log.info("Listening on port \(port)")

            // TODO: Change server exit to not rely on error being thrown
            repeat {
                Log.verbose("listen on repeat")
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
                throw error
            }
        }
    }
    
    /// Handle a new client HTTP request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    func handleClientRequest(socket clientSocket: Socket, fromKeepAlive: Bool=false) {

        guard let delegate = delegate else {
            return
        }
        
        socketManager.handle(socket: clientSocket, using: delegate)
    }
    
    /// Wait for all of the listeners to stop.
    ///
    /// - todo: Note that this calls the ListenerGroup object, and is left in for
    /// backwards compability reasons. Can be safely removed once IBM-Swift/Kitura/Kitura.swift 
    /// is patched to directly talk to ListenerGroup.
    public static func waitForListeners() {
        ListenerGroup.waitForListeners()
    }
}
