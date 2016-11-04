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
    /// - Parameter port: port number for new connections (ex. 9000)
    /// - Parameter errorHandler: optional callback for error handling
    ///
    public func listen(port: Int, errorHandler: ((Swift.Error) -> Void)? = nil) {
        self.port = port

        do {
            self.listenSocket = try Socket.create()
        } catch {
            if let callback = errorHandler {
                callback(error)
            } else {
                Log.error("Error creating socket: \(error)")
            }

            self.state = .failed
            self.lifecycleListener.performFailCallbacks(with: error)
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

                self.state = .failed
                self.lifecycleListener.performFailCallbacks(with: error)
            }
        })

        ListenerGroup.enqueueAsynchronously(on: DispatchQueue.global(), block: queuedBlock)

    }

    /// Static method to create a new `FastCGIServer` and have it listen for conenctions
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for FastCGI/HTTP connections
    /// - Parameter errorHandler: optional callback for error handling
    ///
    /// - Returns: a new `FastCGIServer` instance
    public static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)? = nil) -> FastCGIServer {

        let server = FastCGI.createServer()
        server.delegate = delegate
        server.listen(port: port, errorHandler: errorHandler)
        return server

    }

    /// Handles instructions for listening on a socket
    ///
    /// - Parameter socket: socket to use for connecting
    /// - Parameter port: number to listen on
    private func listen(socket: Socket, port: Int) throws {
        try socket.listen(on: port, maxBacklogSize: maxPendingConnections)
        self.state = .started
        Log.info("Listening on port \(port) (FastCGI)")

        self.lifecycleListener.performStartCallbacks()
        defer {
            self.lifecycleListener.performStopCallbacks()
        }

        repeat {
            do {
                let clientSocket = try socket.acceptClientConnection()
                Log.verbose("Accepted FastCGI connection from: " +
                    "\(clientSocket.remoteHostname):\(clientSocket.remotePort)")
                handleClientRequest(socket: clientSocket)
            } catch let error as Socket.Error {
                if self.state == .stopped {
                    if error.errorCode == Int32(Socket.SOCKET_ERR_ACCEPT_FAILED) {
                        Log.info("FastCGI Server has stopped listening")
                    } else {
                        Log.warning("Error in FastCGI socket.acceptClientConnection after server stopped: \(error)")
                    }
                } else {
                    Log.error("Error in FastCGI socket.acceptClientConnection: \(error)")
                }
            }
        } while self.state == .started && socket.isListening
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

    /// Stop listening for new connections
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
}
