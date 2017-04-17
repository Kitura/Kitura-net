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

#if os(Linux)
  import Signals
#endif

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
    private var socketManager: IncomingSocketManager?

    /// SSL cert configs for handling client requests
    public var sslConfig: SSLService.Configuration?

    fileprivate let lifecycleListener = ServerLifecycleListener()
    
    private static let dummyServerDelegate = HTTPDummyServerDelegate()

    public init() {
        #if os(Linux)
            // On Linux, it is not possible to set SO_NOSIGPIPE on the socket, nor is it possible
            // to pass MSG_NOSIGNAL when writing via SSL_write(). Instead, we will receive it but
            // ignore it. This happens when a remote receiver closes a socket we are to writing to.
            Signals.trap(signal: .pipe) {
                _ in
                Log.info("Receiver closed socket, SIGPIPE ignored")
            }
        #endif
    }

    /// Listens for connections on a socket
    ///
    /// - Parameter on: port number for new connections (eg. 8080)
    public func listen(on port: Int) throws {
        self.port = port
        do {
            let socket = try Socket.create()
            self.listenSocket = socket

            // If SSL config has been created,
            // create and attach the SSLService delegate to the socket
            if let sslConfig = sslConfig {
                socket.delegate = try SSLService(usingConfiguration: sslConfig);
            }

            try socket.listen(on: port, maxBacklogSize: maxPendingConnections)

            let socketManager = IncomingSocketManager()
            self.socketManager = socketManager

            // If a random (ephemeral) port number was requested, get the listening port
            let listeningPort = Int(socket.listeningPort)
            if listeningPort != port {
                self.port = listeningPort
                // We should only expect a different port if the requested port was zero.
                if port != 0 {
                    Log.error("Listening port \(listeningPort) does not match requested port \(port)")
                }
            }

            if let delegate = socket.delegate {
                Log.info("Listening on port \(self.port!) (delegate: \(delegate))")
            } else {
                Log.info("Listening on port \(self.port!)")
            }

            // set synchronously to avoid contention in back to back server start/stop calls
            self.state = .started
            self.lifecycleListener.performStartCallbacks()

            let queuedBlock = DispatchWorkItem(block: {
                self.listen(listenSocket: socket, socketManager: socketManager)
                self.lifecycleListener.performStopCallbacks()
            })

            ListenerGroup.enqueueAsynchronously(on: DispatchQueue.global(), block: queuedBlock)
        }
        catch let error {
            self.state = .failed
            self.lifecycleListener.performFailCallbacks(with: error)
            throw error
        }
    }

    /// Static method to create a new HTTPServer and have it listen for connections.
    ///
    /// - Parameter on: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for HTTP connections
    ///
    /// - Returns: a new `HTTPServer` instance
    public static func listen(on port: Int, delegate: ServerDelegate?) throws -> HTTPServer {
        let server = HTTP.createServer()
        server.delegate = delegate
        try server.listen(on: port)
        return server
    }

    /// Listens for connections on a socket
    ///
    /// - Parameter port: port number for new connections (eg. 8080)
    /// - Parameter errorHandler: optional callback for error handling
    @available(*, deprecated, message: "use 'listen(on:) throws' with 'server.failed(callback:)' instead")
    public func listen(port: Int, errorHandler: ((Swift.Error) -> Void)? = nil) {
        do {
            try listen(on: port)
        }
        catch let error {
            if let callback = errorHandler {
                callback(error)
            } else {
                Log.error("Error listening on port \(port): \(error)")
            }
        }
    }

    /// Static method to create a new HTTPServer and have it listen for connections.
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for HTTP connections
    /// - Parameter errorHandler: optional callback for error handling
    ///
    /// - Returns: a new `HTTPServer` instance
    @available(*, deprecated, message: "use 'listen(on:delegate:) throws' with 'server.failed(callback:)' instead")
    public static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)? = nil) -> HTTPServer {
        let server = HTTP.createServer()
        server.delegate = delegate
        server.listen(port: port, errorHandler: errorHandler)
        return server
    }

    /// Listen on socket while server is started and pass on to socketManager to handle
    private func listen(listenSocket: Socket, socketManager: IncomingSocketManager) {
        repeat {
            do {
                let clientSocket = try listenSocket.acceptClientConnection()
                Log.debug("Accepted HTTP connection from: " +
                    "\(clientSocket.remoteHostname):\(clientSocket.remotePort)")

                socketManager.handle(socket: clientSocket,
                                     processor: IncomingHTTPSocketProcessor(socket: clientSocket,
                                                        using: delegate ?? HTTPServer.dummyServerDelegate))
            } catch let error {
                if self.state == .stopped {
                    if let socketError = error as? Socket.Error {
                        if socketError.errorCode == Int32(Socket.SOCKET_ERR_ACCEPT_FAILED) {
                            Log.info("Server has stopped listening")
                        } else {
                            Log.warning("Socket.Error accepting client connection after server stopped: \(error)")
                        }
                    } else {
                        Log.warning("Error accepting client connection after server stopped: \(error)")
                    }
                } else {
                    Log.error("Error accepting client connection: \(error)")
                    self.lifecycleListener.performClientConnectionFailCallbacks(with: error)
                }
            }
        } while self.state == .started && listenSocket.isListening

        if self.state == .started {
            Log.error("listenSocket closed without stop() being called")
            stop()
        }
    }

    /// Stop listening for new connections.
    public func stop() {
        self.state = .stopped

        listenSocket?.close()
        listenSocket = nil

        socketManager?.stop()
        socketManager = nil
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

    /// Add a new listener for when listenSocket.acceptClientConnection throws an error
    ///
    /// - Parameter callback: The listener callback that will run
    ///
    /// - Returns: a Server instance
    @discardableResult
    public func clientConnectionFailed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addClientConnectionFailCallback(callback)
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
    
    /// A Dummy `ServerDelegate` used when the user didn't supply a delegate, but has registerd
    /// at least one ConnectionUpgradeFactory. This `ServerDelegate` will simply return 404 for
    /// any requests it is asked to process.
    private class HTTPDummyServerDelegate: ServerDelegate {
        /// Handle new incoming requests to the server
        ///
        /// - Parameter request: The ServerRequest class instance for working with this request.
        ///                     The ServerRequest object enables you to get the query parameters, headers, and body amongst other
        ///                     information about the incoming request.
        /// - Parameter response: The ServerResponse class instance for working with this request.
        ///                     The ServerResponse object enables you to build and send your response to the client who sent
        ///                     the request. This includes headers, the body, and the response code.
        func handle(request: ServerRequest, response: ServerResponse){
            do {
                response.statusCode = .notFound
                let theBody = "Path not found"
                response.headers["Content-Type"] = ["text/plain"]
                response.headers["Content-Length"] = [String(theBody.lengthOfBytes(using: .utf8))]
                try response.write(from: theBody)
                try response.end()
            }
            catch {
                Log.error("Failed to send the response. Error = \(error)")
            }
        }
    }
}
