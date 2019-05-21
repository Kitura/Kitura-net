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

#if os(Linux)
  import Signals
#endif

/**
A server that listens for incoming HTTP requests that are sent using the FastCGI protocol. This can be used to create a new `FastCGIServer` and have it listen for conenctions and handle a new client FastCGI request.

### Usage Example: ###
````swift
//Create a `FastCGI` server on a specified port.
let server = try FastCGIServer.listen(on: port, delegate: delegate)
````
*/
public class FastCGIServer: Server {

    public typealias ServerType = FastCGIServer

    /**
     The `ServerDelegate` to handle incoming requests.
     
     ### Usage Example: ###
     ````swift
     server.delegate = delegate
     ````
     */
    public var delegate: ServerDelegate?

    /**
     Port number for listening for new connections
     
     ### Usage Example: ###
     ````swift
     self.port = port
     ````
     */
    public private(set) var port: Int?

    /// The address of the network interface to listen on. Defaults to nil, which means this server will listen on all
    /// interfaces.
    public private(set) var address: String?

    /**
     A server state.
     
     ### Usage Example: ###
     ````swift
     self.state = .started
     ````
     */
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
    
    /**
     Whether or not this server allows port reuse (default: disallowed)
     
     ### Usage Example: ###
     ````swift
     server.allowPortReuse = allowPortReuse
     ````
     */
    public var allowPortReuse: Bool = false

    fileprivate let lifecycleListener = ServerLifecycleListener()

    /// Creates a FastCGI server instance.
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

    /**
     Listens for connections on a socket
     
     - Parameter on: port number for new connections
     - Parameter address: The address of a network interface to listen on, for example "localhost". The default is nil,
                 which listens for connections on all interfaces.

     ### Usage Example: ###
     ````swift
     try server.listen(on: port, address: "localhost")
     ````
     */
    public func listen(on port: Int, address: String? = nil) throws {
        self.port = port
        self.address = address
        do {
            let socket = try Socket.create()
            self.listenSocket = socket

            try socket.listen(on: port, maxBacklogSize: maxPendingConnections, allowPortReuse: self.allowPortReuse)
            Log.info("Listening on port \(port)")
            Log.verbose("Options for port \(port): maxPendingConnections: \(maxPendingConnections), allowPortReuse: \(self.allowPortReuse)")

            // set synchronously to avoid contention in back to back server start/stop calls
            self.state = .started
            self.lifecycleListener.performStartCallbacks()

            let queuedBlock = DispatchWorkItem(block: {
                self.listen(listenSocket: socket)
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

    /**
     Static method to create a new `FastCGIServer` and have it listen for conenctions

     - Parameter on: port number for accepting new connections
     - Parameter address: The address of a network interface to listen on, for example "localhost". The default is nil,
                 which listens for connections on all interfaces.
     - Parameter delegate: the delegate handler for FastCGI/HTTP connections

     - Returns: a new `FastCGIServer` instance

     ### Usage Example: ###
     ````swift
     let server = try FastCGIServer.listen(on: port, address: "localhost", delegate: delegate)
     ````
     */
    public static func listen(on port: Int, address: String? = nil, delegate: ServerDelegate?) throws -> FastCGIServer {
        let server = FastCGI.createServer()
        server.delegate = delegate
        try server.listen(on: port, address: address)
        return server
    }

    /**
     Listens for connections on a socket
     
     - Parameter port: port number for new connections (ex. 9000)
     - Parameter errorHandler: optional callback for error handling
     
     ### Usage Example: ###
     ````swift
     server.listen(port: port, errorHandler: errorHandler)
     ````
     */
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
    
    /**
     Static method to create a new `FastCGIServer` and have it listen for conenctions
     
     - Parameter port: port number for accepting new connections
     - Parameter delegate: the delegate handler for FastCGI/HTTP connections
     - Parameter errorHandler: optional callback for error handling
     
     - Returns: a new `FastCGIServer` instance
     
     ### Usage Example: ###
     ````swift
     let server = FastCGIServer.listen(port: port, delegate: delegate, errorHandler: errorHandler)
     ````
     */
    @available(*, deprecated, message: "use 'listen(on:delegate:) throws' with 'server.failed(callback:)' instead")
    public static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)? = nil) -> FastCGIServer {
        let server = FastCGI.createServer()
        server.delegate = delegate
        server.listen(port: port, errorHandler: errorHandler)
        return server

    }

    /// Listen on socket while server is started
    private func listen(listenSocket: Socket) {
        repeat {
            do {
                let clientSocket = try listenSocket.acceptClientConnection()
                Log.debug("Accepted FastCGI connection from: " +
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
        } while self.state == .started && listenSocket.isListening

        if self.state == .started {
            Log.error("listenSocket closed without stop() being called")
            stop()
        }
    }

    /// Handle a new client FastCGI request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    private func handleClientRequest(socket clientSocket: Socket) {

        DispatchQueue.global().async() {
            let request = FastCGIServerRequest(socket: clientSocket)
            let response = FastCGIServerResponse(socket: clientSocket, request: request)

            request.parse() { status in
                switch status {
                case .success:
                    self.sendMultiplexRequestRejections(request: request, response: response)
                    Monitor.delegate?.started(request: request, response: response)
                    (self.delegate ?? FastCGIDummyServerDelegate()).handle(request: request, response: response)
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
                    // as they all result in simply closing the connection anyways.
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

    /**
     Stop listening for new connections.
     
     ### Usage Example: ###
     ````swift
     server.stop()
     ````
     */
    public func stop() {
        self.state = .stopped
        listenSocket?.close()
        listenSocket = nil
    }

    /**
     Add a new listener for server being started
     
     - Parameter callback: The listener callback that will run on server successfull start-up
     
     - Returns: a `FastCGIServer` instance
     
     ### Usage Example: ###
     ````swift
     server.started(request: request, response: response)
     ````
     */
    @discardableResult
    public func started(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStartCallback(perform: self.state == .started, callback)
        return self
    }

    /**
     Add a new listener for server being stopped
     
     - Parameter callback: The listener callback that will run when server stops
     
     - Returns: a `FastCGIServer` instance
     
     ### Usage Example: ###
     ````swift
     server.stopped(request: request, response: response)
     ````
     */
    @discardableResult
    public func stopped(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStopCallback(perform: self.state == .stopped, callback)
        return self
    }

    /**
     Add a new listener for server throwing an error
     
     - Parameter callback: The listener callback that will run when server throws an error
     
     - Returns: a `FastCGIServer` instance
     
     ### Usage Example: ###
     ````swift
     server.failed(request: request, response: response)
     ````
     */
    @discardableResult
    public func failed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addFailCallback(callback)
        return self
    }

    /**
     Add a new listener for when listenSocket.acceptClientConnection throws an error
     
     - Parameter callback: The listener callback that will run
     
     - Returns: a Server instance
     
     ### Usage Example: ###
     ````swift
     server.clientConnectionFailed() { error in
         ...
     }
     ````
     */
    @discardableResult
    public func clientConnectionFailed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addClientConnectionFailCallback(callback)
        return self
    }
    
    /// A Dummy `ServerDelegate` used when the user didn't supply a delegate, but has registerd
    /// at least one ConnectionUpgradeFactory. This `ServerDelegate` will simply return 404 for
    /// any requests it is asked to process.
    private class FastCGIDummyServerDelegate: ServerDelegate {
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
                try response.end()
            }
            catch {
                Log.error("Failed to send the response. Error = \(error)")
            }
        }
    }
}
