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
public class HTTPServer: Server {

    public typealias ServerType = HTTPServer

    /// HTTP `ServerDelegate`.
    public var delegate: ServerDelegate?

    /// Port number for listening for new connections.
    public private(set) var port: Int?

    /// A server state.
    public private(set) var state: ServerState = .unknown

    /// TCP socket used for listening for new connections
    private var listenSocket: Socket?

    /// Maximum number of pending connections
    private let maxPendingConnections = 100

    /// Incoming socket handler
    private let socketManager = IncomingSocketManager()

    /// SSL cert configs for handling client requests
    public var sslConfig: SSLService.Configuration?

    fileprivate let lifecycleListener = ServerLifecycleListener()


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
        }
        catch let error {
            if let callback = errorHandler {
                callback(error)
            } else {
                if let socketError = error as? Socket.Error {
                    Log.error("Error creating socket: \(socketError)")
                } else if let sslError = error as? SSLError {
                    // we have to catch SSLErrors separately since we are
                    // calling SSLService.Configuration
                    Log.error("Error in SSLService init: \(sslError)")
                } else {
                    Log.error("Unexpected error: \(error)")
                }
            }

            self.state = .failed
            self.lifecycleListener.performFailCallbacks(with: error)

            return // TODO - should add throws to listen signature so we can propagate this error up
        }

        let queuedBlock = DispatchWorkItem(block: {
            do {
                try self.listen(socket: self.listenSocket!, port: port)
            } catch {
                if let callback = errorHandler {
                    callback(error)
                } else {
                    Log.error("Error listening on socket: \(error)")
                }

                self.state = .failed
                self.lifecycleListener.performFailCallbacks(with: error)
            }
        })

        ListenerGroup.enqueueAsynchronously(on: DispatchQueue.global(), block: queuedBlock)
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
    private func listen(socket: Socket, port: Int) throws {
        try socket.listen(on: port, maxBacklogSize: maxPendingConnections)
        self.state = .started
        if let delegate = socket.delegate {
            Log.info("Listening on port \(port) (delegate: \(delegate))")
        } else {
            Log.info("Listening on port \(port)")
        }

        self.lifecycleListener.performStartCallbacks()
        defer {
            self.lifecycleListener.performStopCallbacks()
        }

        repeat {
            do {
                let clientSocket = try socket.acceptClientConnection()
                Log.verbose("Accepted connection from: " +
                    "\(clientSocket.remoteHostname):\(clientSocket.remotePort)")
                handleClientRequest(socket: clientSocket)
            } catch let error as Socket.Error {
                if self.state == .stopped {
                    if error.errorCode == Int32(Socket.SOCKET_ERR_ACCEPT_FAILED) {
                        Log.info("Server has stopped listening")
                    } else {
                        Log.warning("Error in socket.acceptClientConnection after server stopped: \(error)")
                    }
                } else {
                    Log.error("Error in socket.acceptClientConnection: \(error)")
                }
            }
        } while self.state == .started && socket.isListening
    }

    /// Handle a new client HTTP request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    private func handleClientRequest(socket clientSocket: Socket, fromKeepAlive: Bool=false) {

        guard let delegate = delegate else {
            return
        }

        socketManager.handle(socket: clientSocket, processor: IncomingHTTPSocketProcessor(socket: clientSocket, using: delegate))
    }

    /// Stop listening for new connections.
    public func stop() {
        defer {
            delegate = nil
        }
        if let listenSocket = listenSocket {
            self.state = .stopped
            listenSocket.close()
        }
    }

    /// Add a new listener for server beeing started
    ///
    /// - Parameter callback: The listener callback that will run on server successfull start-up
    ///
    /// - Returns: a `HTTPServer` instance
    @discardableResult
    public func started(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStartCallback(perform: self.state == .started, callback)
        return self
    }

    /// Add a new listener for server beeing stopped
    ///
    /// - Parameter callback: The listener callback that will run when server stops
    ///
    /// - Returns: a `HTTPServer` instance
    @discardableResult
    public func stopped(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStopCallback(perform: self.state == .stopped, callback)
        return self
    }

    /// Add a new listener for server throwing an error
    ///
    /// - Parameter callback: The listener callback that will run when server throws an error
    ///
    /// - Returns: a `HTTPServer` instance
    @discardableResult
    public func failed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addFailCallback(callback)
        return self
    }

    /// Wait for all of the listeners to stop.
    ///
    /// - todo: Note that this calls the ListenerGroup object, and is left in for
    /// backwards compability reasons. Can be safely removed once IBM-Swift/Kitura/Kitura.swift
    /// is patched to directly talk to ListenerGroup.
    @available(*, deprecated, message:"Will be removed in future versions. Use ListenerGroup.waitForListeners() directly.")
    public static func waitForListeners() {
        ListenerGroup.waitForListeners()
    }
}
