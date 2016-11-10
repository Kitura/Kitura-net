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

/// A common protocol for Kitura-net Servers
public protocol Server {

    /// A type that will be returned by static `listen` method
    associatedtype ServerType

    /// A `ServerDelegate` used for request handling
    var delegate: ServerDelegate? { get set }

    /// Port number for listening for new connections.
    var port: Int? { get }

    /// A server state.
    var state: ServerState { get }

    /// Listen for connections on a socket.
    ///
    /// - Parameter on: port number for new connections (eg. 8090)
    func listen(on port: Int) throws

    /// Static method to create a new Server and have it listen for connections.
    ///
    /// - Parameter on: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for HTTP connections
    ///
    /// - Returns: a new Server instance
    static func listen(on port: Int, delegate: ServerDelegate) throws -> ServerType

    /// Listen for connections on a socket.
    ///
    /// - Parameter port: port number for new connections (eg. 8090)
    /// - Parameter errorHandler: optional callback for error handling
    @available(*, deprecated, message: "use 'listen(on:) throws' with 'server.failed(callback:)' instead")
    func listen(port: Int, errorHandler: ((Swift.Error) -> Void)?)

    /// Static method to create a new Server and have it listen for connections.
    ///
    /// - Parameter port: port number for accepting new connections
    /// - Parameter delegate: the delegate handler for HTTP connections
    /// - Parameter errorHandler: optional callback for error handling
    ///
    /// - Returns: a new Server instance
    @available(*, deprecated, message: "use 'listen(on:delegate:) throws' with 'server.failed(callback:)' instead")
    static func listen(port: Int, delegate: ServerDelegate, errorHandler: ((Swift.Error) -> Void)?) -> ServerType

    /// Stop listening for new connections.
    func stop()

    /// Add a new listener for server beeing started
    ///
    /// - Parameter callback: The listener callback that will run on server successfull start-up
    ///
    /// - Returns: a Server instance
    @discardableResult
    func started(callback: @escaping () -> Void) -> Self

    /// Add a new listener for server beeing stopped
    ///
    /// - Parameter callback: The listener callback that will run when server stops
    ///
    /// - Returns: a Server instance
    @discardableResult
    func stopped(callback: @escaping () -> Void) -> Self

    /// Add a new listener for server throwing an error
    ///
    /// - Parameter callback: The listener callback that will run when server throws an error
    ///
    /// - Returns: a Server instance
    @discardableResult
    func failed(callback: @escaping (Swift.Error) -> Void) -> Self

    /// Add a new listener for when listenSocket.acceptClientConnection throws an error
    ///
    /// - Parameter callback: The listener callback that will run
    ///
    /// - Returns: a Server instance
    @discardableResult
    func clientConnectionFailed(callback: @escaping (Swift.Error) -> Void) -> Self
}
