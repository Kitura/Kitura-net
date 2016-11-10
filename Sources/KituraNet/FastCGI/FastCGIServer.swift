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

import Socket
import LoggerAPI

/// A server that listens for incoming HTTP requests that are sent using the FastCGI
/// protocol.
public class FastCGIServer: Server {

    public typealias ServerType = FastCGIServer

    /// The `ServerDelegate` to handle incoming requests.
    public var delegate: ServerDelegate?

    /// Port number for listening for new connections
    public private(set) var port: Int?

    /// A server state.
    public private(set) var state: ServerState = .unknown

    /// Retrieve an appropriate connection backlog value for our listen socket.
    /// This log is taken from Nginx, and tests out with good results.
    private lazy var maxPendingConnections: Int = {
        #if os(Linux)
            return 511
        #else
            return -1
        #endif
    }()

    /// TCP socket used for listening for new connections
    private var listenSocket: Socket?

    fileprivate let lifecycleListener = ServerLifecycleListener()

    /// Listens for connections on a socket
    ///
    /// - Parameter on: port number for new connections
    public func listen(on port: Int) throws {
        self.port = port
        do {
            self.listenSocket = try Socket.create()

            try listenSocket!.listen(on: port, maxBacklogSize: maxPendingConnections)
            Log.info("Listening on port \(port)")

            let queuedBlock = DispatchWorkItem(block: {
                self.state = .started
                self.lifecycleListener.performStartCallbacks()
                self.listen()
                self.lifecycleListener.performStopCallbacks()
                self.listenSocket = nil
            })

            ListenerGroup.enqueueAsynchronously(on: DispatchQueue.global(), block: queuedBlock)
        }
        catch let error {
            self.state = .failed
            self.lifecycleListener.performFailCallbacks(with: error)
            throw error
        }
    }

    /// Static method to create a new `FastCGIServer` and have it listen for conenctions
    ///
    /// - Parameter on: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for FastCGI/HTTP connections
    ///
    /// - Returns: a new `FastCGIServer` instance
    public static func listen(on port: Int, delegate: ServerDelegate) throws -> FastCGIServer {
        let server = FastCGI.createServer()
        server.delegate = delegate
        try server.listen(on: port)
        return server
    }

    /// Listens for connections on a socket
    ///
    /// - Parameter port: port number for new connections (ex. 9000)
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

    /// Static method to create a new `FastCGIServer` and have it listen for conenctions
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for FastCGI/HTTP connections
    /// - Parameter errorHandler: optional callback for error handling
    ///
    /// - Returns: a new `FastCGIServer` instance
    @available(*, deprecated, message: "use 'listen(on:delegate:) throws' with 'server.failed(callback:)' instead")
    public static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)? = nil) -> FastCGIServer {
        let server = FastCGI.createServer()
        server.delegate = delegate
        server.listen(port: port, errorHandler: errorHandler)
        return server

    }

    /// Listen on socket while server is started
    private func listen() {
        repeat {
            do {
                let clientSocket = try self.listenSocket!.acceptClientConnection()
                Log.verbose("Accepted connection from: " +
                    "\(clientSocket.remoteHostname):\(clientSocket.remotePort)")
                handleClientRequest(socket: clientSocket)
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
        } while self.state == .started && self.listenSocket!.isListening

        if self.state == .started {
            Log.error("listenSocket closed without stop() being called")
            stop()
        }
    }

    /// Handle a new client FastCGI request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    private func handleClientRequest(socket clientSocket: Socket) {

        guard let delegate = delegate else {
            return
        }

        DispatchQueue.global().async() {
            let request = FastCGIServerRequest(socket: clientSocket)
            let response = FastCGIServerResponse(socket: clientSocket, request: request)

            request.parse() { status in
                switch status {
                case .success:
                    self.sendMultiplexRequestRejections(request: request, response: response)
                    delegate.handle(request: request, response: response)
                    break
                case .unsupportedRole:
                    // response.unsupportedRole() - not thrown
                    do {
                        try response.rejectUnsupportedRole()
                    } catch {}
                    clientSocket.close()
                    break
                default:
                    // we just want to ignore every other status for now
                    // as they all result in simply closing the conncetion anyways.
                    clientSocket.close()
                    break
                }
            }

        }
    }

    /// Send multiplex request rejections
    private func sendMultiplexRequestRejections(request: FastCGIServerRequest, response: FastCGIServerResponse) {
        if request.extraRequestIds.count > 0 {
            for requestId in request.extraRequestIds {
                do {
                    try response.rejectMultiplexConnecton(requestId: requestId)
                } catch {}
            }
        }
    }

    /// Stop listening for new connections.
    public func stop() {
        self.state = .stopped
        listenSocket?.close()
    }

    /// Add a new listener for server beeing started
    ///
    /// - Parameter callback: The listener callback that will run on server successfull start-up
    ///
    /// - Returns: a `FastCGIServer` instance
    @discardableResult
    public func started(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStartCallback(perform: self.state == .started, callback)
        return self
    }

    /// Add a new listener for server beeing stopped
    ///
    /// - Parameter callback: The listener callback that will run when server stops
    ///
    /// - Returns: a `FastCGIServer` instance
    @discardableResult
    public func stopped(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStopCallback(perform: self.state == .stopped, callback)
        return self
    }

    /// Add a new listener for server throwing an error
    ///
    /// - Parameter callback: The listener callback that will run when server throws an error
    ///
    /// - Returns: a `FastCGIServer` instance
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
}
