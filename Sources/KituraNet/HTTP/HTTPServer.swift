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

/**
An HTTP server that listens for connections on a socket.

### Usage Example: ###
````swift
 //Create a server that listens for connections on a specified socket.
 let server = try HTTPServer.listen(on: 0, delegate: delegate)
 ...
 //Stop the server.
 server.stop()
````
*/
public class HTTPServer: Server {

    public typealias ServerType = HTTPServer

    /**
     HTTP `ServerDelegate`.
     
     ### Usage Example: ###
     ````swift
     httpServer.delegate = self
     ````
     */
    public var delegate: ServerDelegate?

    /// The TCP port on which this server listens for new connections. If `nil`, this server does not listen on a TCP socket.
    public private(set) var port: Int?

    /// The address of the network interface to listen on. Defaults to nil, which means this server will listen on all
    /// interfaces.
    public private(set) var address: String?

    /// The Unix domain socket path on which this server listens for new connections. If `nil`, this server does not listen on a Unix socket.
    public private(set) var unixDomainSocketPath: String?

    /// The types of listeners we currently support.
    private enum ListenerType {
        case inet(Int, String?) // port, node
        case unix(String)
    }

    /**
     A server state
     
     ### Usage Example: ###
     ````swift
     if(httpSever.state == .unknown) {
        httpServer.stop()
     }
     ````
     */
    public private(set) var state: ServerState = .unknown

    /// TCP socket used for listening for new connections
    private var listenSocket: Socket?

    /**
     Whether or not this server allows port reuse (default: disallowed).
     
     ### Usage Example: ###
     ````swift
     httpServer.allowPortReuse = true
     ````
     */
    public var allowPortReuse: Bool = false

    /// Maximum number of pending connections
    private let maxPendingConnections = 100

    /**
     Controls the maximum number of requests per Keep-Alive connection.
     
     ### Usage Example: ###
     ````swift
     httpServer.keepAliveState = .unlimited
     ````
     */
    public var keepAliveState: KeepAliveState = .unlimited
    
    /// Controls policies relating to incoming connections and requests.
    public var connectionPolicy: IncomingSocketOptions = IncomingSocketOptions() {
        didSet {
            self.socketManager?.connectionPolicy = connectionPolicy
        }
    }

    /// Incoming socket handler
    private var socketManager: IncomingSocketManager?

    /**
     SSL cert configuration for handling client requests.
     
     ### Usage Example: ###
     ````swift
     httpServer.sslConfig = sslConfiguration
     ````
     */
    public var sslConfig: SSLService.Configuration?

    fileprivate let lifecycleListener = ServerLifecycleListener()
    
    private static let dummyServerDelegate = HTTPDummyServerDelegate()
    
    private static var incomingSocketProcessorCreatorRegistry = Dictionary<String, IncomingSocketProcessorCreator>()
    
    // Initialize the one time initialization struct to cause one time initializations to occur
    static private let oneTime = HTTPServerOneTimeInitializations()

    /**
     Creates an HTTP server object.
     
     ### Usage Example: ###
     ````swift
     let server = HTTPServer()
     server.listen(on: 8080)
     ````
     */
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
        _ = HTTPServer.oneTime
    }

    /**
     Listens for connections on a TCP socket.
     
     ### Usage Example: ###
     ````swift
     try server.listen(on: 8080, address: "localhost")
     ````
     
     - Parameter port: Port number for new connections, e.g. 8080
     - Parameter address: The address of a network interface to listen on, for example "localhost". The default is nil,
                 which listens for connections on all interfaces.
     */
    public func listen(on port: Int, address: String? = nil) throws {
        self.port = port
        self.address = address
        try listen(.inet(port, address))
    }

    /**
     Listens for connections on a Unix socket.

     ### Usage Example: ###
     ````swift
     try server.listen(unixDomainSocketPath: "/my/path")
     ````

     - Parameter unixDomainSocketPath: Unix socket path for new connections, eg. "/my/path"
     */
    public func listen(unixDomainSocketPath: String) throws {
        self.unixDomainSocketPath = unixDomainSocketPath
        try listen(.unix(unixDomainSocketPath))
    }

    private func listen(_ listener: ListenerType) throws {
        do {
            let socket: Socket
            switch listener {
            case .inet:
                socket = try Socket.create(family: .inet)
            case .unix:
                socket = try Socket.create(family: .unix)
            }
           self.listenSocket = socket

            // If SSL config has been created,
            // create and attach the SSLService delegate to the socket
            if let sslConfig = sslConfig {
                socket.delegate = try SSLService(usingConfiguration: sslConfig);
            }

            let listenerDescription: String
            switch listener {
            case .inet(let port, let node):
                try socket.listen(on: port, maxBacklogSize: maxPendingConnections, allowPortReuse: self.allowPortReuse,
                                  node: node)
                // If a random (ephemeral) port number was requested, get the listening port
                let listeningPort = Int(socket.listeningPort)
                if listeningPort != port {
                    self.port = listeningPort
                    // We should only expect a different port if the requested port was zero.
                    if port != 0 {
                        Log.error("Listening port \(listeningPort) does not match requested port \(port)")
                    }
                }
                listenerDescription = "port \(listeningPort)"
            case .unix(let path):
                try socket.listen(on: path, maxBacklogSize: maxPendingConnections)
                listenerDescription = "path \(path)"
            }

            let socketManager = IncomingSocketManager()
            socketManager.connectionPolicy = self.connectionPolicy
            self.socketManager = socketManager

            if let delegate = socket.delegate {
                #if os(Linux)
                    // Add the list of supported ALPN protocols to the SSLServiceDelegate
                    for (protoName, _) in HTTPServer.incomingSocketProcessorCreatorRegistry {
                        socket.delegate?.addSupportedAlpnProtocol(proto: protoName)
                    }
                #endif
                
                Log.info("Listening on \(listenerDescription) (delegate: \(delegate))")
                Log.verbose("Options for \(listenerDescription): delegate: \(delegate), maxPendingConnections: \(maxPendingConnections), allowPortReuse: \(self.allowPortReuse)")
            } else {
                Log.info("Listening on \(listenerDescription)")
                Log.verbose("Options for \(listenerDescription): maxPendingConnections: \(maxPendingConnections), allowPortReuse: \(self.allowPortReuse)")
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

    /**
     Static method to create a new HTTP server and have it listen for connections.
     
     ### Usage Example: ###
     ````swift
     let server = HTTPServer.listen(on: 8080, address: "localhost", delegate: self)
     ````
     
     - Parameter on: Port number for accepting new connections.
     - Parameter address: The address of a network interface to listen on, for example "localhost". The default is nil,
                 which listens for connections on all interfaces.
     - Parameter delegate: The delegate handler for HTTP connections.
     
     - Returns: A new instance of a `HTTPServer`.
     */
    public static func listen(on port: Int, address: String? = nil, delegate: ServerDelegate?) throws -> HTTPServer {
        let server = HTTP.createServer()
        server.delegate = delegate
        try server.listen(on: port, address: address)
        return server
    }

    /**
     Static method to create a new HTTP server and have it listen for connections on a Unix domain socket.

     ### Usage Example: ###
     ````swift
     let server = HTTPServer.listen(unixDomainSocketPath: "/my/path", delegate: self)
     ````

     - Parameter unixDomainSocketPath: The path of the Unix domain socket that this server should listen on.
     - Parameter delegate: The delegate handler for HTTP connections.

     - Returns: A new instance of a `HTTPServer`.
     */
    public static func listen(unixDomainSocketPath: String, delegate: ServerDelegate?) throws -> HTTPServer {
        let server = HTTP.createServer()
        server.delegate = delegate
        try server.listen(unixDomainSocketPath: unixDomainSocketPath)
        return server
    }

    /**
     Listen for connections on a socket.
     
     ### Usage Example: ###
     ````swift
     try server.listen(on: 8080, errorHandler: errorHandler)
     ````
     - Parameter port: port number for new connections (eg. 8080)
     - Parameter errorHandler: optional callback for error handling
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
     Static method to create a new HTTPServer and have it listen for connections.
     
     ### Usage Example: ###
     ````swift
     let server = HTTPServer(port: 8080, delegate: self, errorHandler: errorHandler)
     ````
     - Parameter port: port number for new connections (eg. 8080)
     - Parameter delegate: The delegate handler for HTTP connections.
     - Parameter errorHandler: optional callback for error handling
     
     - Returns: A new `HTTPServer` instance.
     */
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
                let clientSocket = try listenSocket.acceptClientConnection(invokeDelegate: false)
                let clientSource = "\(clientSocket.remoteHostname):\(clientSocket.remotePort)"
                if let connectionLimit = self.connectionPolicy.connectionLimit, socketManager.socketHandlerCount >= connectionLimit {
                    // See if any idle sockets can be removed before rejecting this connection
                    socketManager.removeIdleSockets(runNow: true)
                }
                if let connectionLimit = self.connectionPolicy.connectionLimit, socketManager.socketHandlerCount >= connectionLimit {
                    // Connections still at limit, this connection must be rejected
                    let statusCode = HTTPStatusCode.serviceUnavailable.rawValue
                    let statusDescription = HTTP.statusCodes[statusCode] ?? ""
                    _ = try? clientSocket.write(from: "HTTP/1.1 \(statusCode) \(statusDescription)\r\nConnection: Close\r\nContent-Length: 0\r\n\r\n")
                    clientSocket.close()
                    Log.debug("Rejected connection from \(clientSource): Maximum connection limit of \(connectionLimit) reached")
                    continue
                } else {
                    Log.debug("Accepted HTTP connection from: \(clientSource)")
                }
				
                if listenSocket.delegate != nil {
                    DispatchQueue.global().async { [weak self] in
                        guard let strongSelf = self else {
                            Log.info("Cannot initialize client connection from \(clientSource), server has been deallocated")
                            return
                        }
                        do {
                            try strongSelf.initializeClientConnection(clientSocket: clientSocket, listenSocket: listenSocket)
                            strongSelf.handleClientConnection(clientSocket: clientSocket, socketManager: socketManager)
                        } catch let error {
                            if strongSelf.state == .stopped {
                                if let socketError = error as? Socket.Error {
                                    Log.warning("Socket.Error initializing client connection from \(clientSource) after server stopped: \(socketError)")
                                } else {
                                    Log.warning("Error initializing client connection from \(clientSource) after server stopped: \(error)")
                                }
                            } else {
                                Log.error("Error initializing client connection from \(clientSource): \(error)")
                                strongSelf.lifecycleListener.performClientConnectionFailCallbacks(with: error)
                            }
                        }
                    }
                } else {
                    handleClientConnection(clientSocket: clientSocket, socketManager: socketManager)
                }
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

    /// Initializes a newly accepted client connection.
    /// This procedure may involve reading bytes from the client (in the case of an SSL handshake),
    /// so must be done on a separate thread to avoid blocking the listener (Kitura issue #1143).
    ///
    private func initializeClientConnection(clientSocket: Socket, listenSocket: Socket) throws {
        if listenSocket.delegate != nil {
            try listenSocket.invokeDelegateOnAccept(for: clientSocket)
        }
    }

    /// Completes the process of accepting a new client connection. This is either invoked from the
    /// main listen() loop, or in the presence of an SSL delegate, from an async block.
    /// 
    private func handleClientConnection(clientSocket: Socket, socketManager: IncomingSocketManager) {
        #if os(Linux)
            let negotiatedProtocol = clientSocket.delegate?.negotiatedAlpnProtocol ?? "http/1.1"
        #else
            let negotiatedProtocol = "http/1.1"
        #endif
        
        if let incomingSocketProcessorCreator = HTTPServer.incomingSocketProcessorCreatorRegistry[negotiatedProtocol] {
            let serverDelegate = delegate ?? HTTPServer.dummyServerDelegate
            let incomingSocketProcessor: IncomingSocketProcessor?
            switch incomingSocketProcessorCreator {
            case let creator as HTTPIncomingSocketProcessorCreator:
                incomingSocketProcessor = creator.createIncomingSocketProcessor(socket: clientSocket, using: serverDelegate, keepalive: self.keepAliveState)
            default:
                incomingSocketProcessor = incomingSocketProcessorCreator.createIncomingSocketProcessor(socket: clientSocket, using: serverDelegate)
            }
            socketManager.handle(socket: clientSocket, processor: incomingSocketProcessor!)
        }
        else {
            Log.error("Negotiated protocol \(negotiatedProtocol) not supported on this server")
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

        socketManager?.stop()
        socketManager = nil
    }

    /**
     Add a new listener for a server being started.
     
     ### Usage Example: ###
     ````swift
     server.started(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run after a successfull start-up.
     
     - Returns: A `HTTPServer` instance.
     */
    @discardableResult
    public func started(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStartCallback(perform: self.state == .started, callback)
        return self
    }

    /**
     Add a new listener for a server being stopped.
     
     ### Usage Example: ###
     ````swift
     server.stopped(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run when the server stops.
     
     - Returns: A `HTTPServer` instance.
     */
    @discardableResult
    public func stopped(callback: @escaping () -> Void) -> Self {
        self.lifecycleListener.addStopCallback(perform: self.state == .stopped, callback)
        return self
    }

    /**
     Add a new listener for a server throwing an error.
     
     ### Usage Example: ###
     ````swift
     server.started(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run when the server throws an error.
     
     - Returns: A `HTTPServer` instance.
     */
    @discardableResult
    public func failed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addFailCallback(callback)
        return self
    }

    /**
     Add a new listener for when `listenSocket.acceptClientConnection` throws an error.
     
     ### Usage Example: ###
     ````swift
     server.clientConnectionFailed(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run on server after successfull start-up.
     
     - Returns: A `HTTPServer` instance.
     */
    @discardableResult
    public func clientConnectionFailed(callback: @escaping (Swift.Error) -> Void) -> Self {
        self.lifecycleListener.addClientConnectionFailCallback(callback)
        return self
    }

    /**
     Wait for all of the listeners to stop.
     
     ### Usage Example: ###
     ````swift
     server.waitForListeners()
     ````
     
     - todo: This calls the ListenerGroup object, and is left in for backwards compatability. It can be safely removed once Kitura is patched to talk directly to ListenerGroup.
     
     */
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
                response.headers["Content-Length"] = [String(theBody.utf8.count)]
                try response.write(from: theBody)
                try response.end()
            }
            catch {
                Log.error("Failed to send the response. Error = \(error)")
            }
        }
    }
    

    /**
     Register a class that creates `IncomingSockerProcessor`s for use with new incoming sockets.
     
     ### Usage Example: ###
     ````swift
     server.register(incomingSocketProcessorCreator: creator)
     ````
     - Parameter incomingSocketProcessorCreator: An implementation of the `IncomingSocketProcessorCreator` protocol which creates an implementation of the `IncomingSocketProcessor` protocol to process the data from a new incoming socket.

     */
    public static func register(incomingSocketProcessorCreator creator: IncomingSocketProcessorCreator) {
        incomingSocketProcessorCreatorRegistry[creator.name] = creator
    }
    
    /// Singleton struct for one time initializations
    private struct HTTPServerOneTimeInitializations {
        init() {
            HTTPServer.register(incomingSocketProcessorCreator: HTTPIncomingSocketProcessorCreator())
        }
    }
}

