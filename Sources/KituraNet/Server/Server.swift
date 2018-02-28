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

/**
A common protocol for Kitura-net Servers
### Usage Example: ###
````swift
 public class FastCGIServer: Server {
     ...
 }
````
*/
public protocol Server {

    /**
    A type that will be returned by static `listen` method
    ### Usage Example: ###
    ````swift
     static func listen(on port: Int, delegate: ServerDelegate?) throws -> ServerType
        ...
     }
    ````
    */
    associatedtype ServerType
    
    /**
     A `ServerDelegate` used for request handling
     ### Usage Example: ###
     ````swift
     server.delegate = delegate
     ````
     */
    var delegate: ServerDelegate? { get set }
    
    /**
     Port number for listening for new connections.
     ### Usage Example: ###
     ````swift
     let serverPort = server.port
     ````
     */
    var port: Int? { get }
    
    /**
     A server state.
     ### Usage Example: ###
     ````swift
     print(server.state)
     ````
     */
    var state: ServerState { get }

    /**
    Listen for connections on a socket.
    
    - Parameter on: port number for new connections (eg. 8080)
     
    ### Usage Example: ###
     ````swift
     try server.listen(on: port)
     ````
     */
    func listen(on port: Int) throws

    /**
    Static method to create a new Server and have it listen for connections.
    
    - Parameter on: port number for accepting new connections
    - Parameter delegate: the delegate handler for HTTP connections
    
    - Returns: a new Server instance
     
    ### Usage Example: ###
    ````swift
     let server = try FastCGIServer.listen(on: port, delegate: delegate)
     ````
     */
    static func listen(on port: Int, delegate: ServerDelegate?) throws -> ServerType

    /**
    Listen for connections on a socket.
    
    - Parameter port: port number for new connections (eg. 8080)
    - Parameter errorHandler: optional callback for error handling
    
    ### Usage Example: ###
    ````swift
     server.listen(port: port, errorHandler: errorHandler)
    ````
    */
    @available(*, deprecated, message: "use 'listen(on:) throws' with 'server.failed(callback:)' instead")
    func listen(port: Int, errorHandler: ((Swift.Error) -> Void)?)

    /**
    Static method to create a new Server and have it listen for connections.
    
    - Parameter port: port number for accepting new connections
    - Parameter delegate: the delegate handler for HTTP connections
    - Parameter errorHandler: optional callback for error handling
    
    - Returns: a new Server instance
    
    ### Usage Example: ###
    ````swift
     server.listen(port: port, delegate: delegate, errorHandler: errorHandler)
    ````
    */
    @available(*, deprecated, message: "use 'listen(on:delegate:) throws' with 'server.failed(callback:)' instead")
    static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)?) -> ServerType

    /**
     Stop listening for new connections.
     
     ### Usage Example: ###
     ````swift
     server.stop()
     ````
     
     */
    func stop()

    /**
     Add a new listener for a server being started.
     
     ### Usage Example: ###
     ````swift
     server.started(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run after a successfull start-up.
     
     - Returns: A `Server` instance.
     */
    @discardableResult
    func started(callback: @escaping () -> Void) -> Self

    /**
     Add a new listener for a server being stopped.
     
     ### Usage Example: ###
     ````swift
     server.stopped(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run when the server stops.
     
     - Returns: A `Server` instance.
     */
    @discardableResult
    func stopped(callback: @escaping () -> Void) -> Self

    /**
     Add a new listener for a server throwing an error.
     
     ### Usage Example: ###
     ````swift
     server.started(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run when the server throws an error.
     
     - Returns: A `Server` instance.
     */
    @discardableResult
    func failed(callback: @escaping (Swift.Error) -> Void) -> Self

    /**
     Add a new listener for when `listenSocket.acceptClientConnection` throws an error.
     
     ### Usage Example: ###
     ````swift
     server.clientConnectionFailed(callback: callBack)
     ````
     - Parameter callback: The listener callback that will run on server after successfull start-up.
     
     - Returns: A `Server` instance.
     */
    @discardableResult
    func clientConnectionFailed(callback: @escaping (Swift.Error) -> Void) -> Self
}
