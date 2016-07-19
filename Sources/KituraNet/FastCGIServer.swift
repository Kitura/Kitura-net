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
import LoggerAPI

public class FastCGIServer {
 
    ///
    /// Queue for listening and establishing new connections
    ///
    private static var listenerQueue = Queue(type: .parallel, label: "FastCGIServer.listenerQueue")

    ///
    /// Queue for handling client requests
    ///
    private static var clientHandlerQueue = Queue(type: .parallel, label: "FastCGIServer.clientHandlerQueue")

    ///
    /// ServerDelegate
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
    /// Whether the FastCGI server has stopped listening
    ///
    var stopped = false

    ///
    /// Listens for connections on a socket
    ///
    /// - Parameter port: port number for new connections (ex. 9000)
    ///
    public func listen(port: Int) {
        
        self.port = port
        
        do {
            
            self.listenSocket = try Socket.create()
            
        } catch let error as Socket.Error {
            print("FastCGI error reported:\n \(error.description)")
        } catch {
            print("Unexpected FastCGI error...")
        }
        
        let queuedBlock = {
            self.listen(socket: self.listenSocket, port: self.port!)
        }
        
        ListenerGroup.enqueueAsynchronously(on: FastCGIServer.listenerQueue, block: queuedBlock)
        
    }
    
    ///
    /// Static method to create a new FastCGIServer and have it listen for conenctions
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for FastCGI/HTTP connections
    ///
    /// - Returns: a new FastCGIServer instance
    ///
    public static func listen(port: Int, delegate: ServerDelegate) -> FastCGIServer {
        
        let server = FastCGI.createServer()
        server.delegate = delegate
        server.listen(port: port)
        return server
        
    }
    
    //
    // Retrieve an appropriate connection backlog value for our listen socket.
    // This log is taken from Nginx, and tests out with good results.
    //
    private static func getConnectionBacklog() -> Int {
        #if os(Linux)
            return 511
        #else
            return -1
        #endif
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
            
            try socket.listen(on: port, maxBacklogSize:FastCGIServer.getConnectionBacklog())
            Log.info("Listening on port \(port) (FastCGI)")
            
            // TODO: Change server exit to not rely on error being thrown
            repeat {
                let clientSocket = try socket.acceptClientConnection()
                Log.info("Accepted FastCGI connection from: " +
                    "\(clientSocket.remoteHostname):\(clientSocket.remotePort)")
                handleClientRequest(socket: clientSocket)
            } while true
        } catch let error as Socket.Error {
            
            if stopped && error.errorCode == Int32(Socket.SOCKET_ERR_ACCEPT_FAILED) {
                Log.info("FastCGI Server has stopped listening")
            }
            else {
                Log.error("FastCGI Error reported:\n \(error.description)")
            }
        } catch {
            Log.error("Unexpected FastCGI error...")
        }
    }
    
    ///
    /// Send multiplex request rejections
    //
    func sendMultiplexRequestRejections(request: FastCGIServerRequest, response: FastCGIServerResponse) {
        if request.extraRequestIds.count > 0 {
            for requestId in request.extraRequestIds {
                do {
                    try response.rejectMultiplexConnecton(requestId: requestId)
                } catch {}
            }
        }
    }
    
    ///
    /// Handle a new client FastCGI request
    ///
    /// - Parameter clientSocket: the socket used for connecting
    ///
    func handleClientRequest(socket clientSocket: Socket) {
        
        guard let delegate = delegate else {
            return
        }
        
        FastCGIServer.clientHandlerQueue.enqueueAsynchronously() {
            
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
    
    ///
    /// Stop listening for new connections
    ///
    public func stop() {
        
        if let listenSocket = listenSocket {
            stopped = true
            listenSocket.close()
        }
        
    }

    
}
