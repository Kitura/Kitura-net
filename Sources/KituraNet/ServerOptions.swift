/*
 * Copyright IBM Corporation 2019
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

import Foundation
import LoggerAPI

/**
 ServerOptions allows customization of default server policies, including:

 - `requestSizeLimit`: Defines the maximum size of an incoming request, in bytes. If requests are received that are larger than this limit, they will be rejected and the connection will be closed. A value of `nil` means no limit.
 - `connectionLimit`: Defines the maximum number of concurrent connections that a server should accept. Clients attempting to connect when this limit has been reached will be rejected. A value of `nil` means no limit.

 The server can optionally respond to the client with a message in either of these cases. This message can be customized by defining `requestSizeResponseGenerator` and `connectionResponseGenerator`.

 Example usage:
 ```
 let server = HTTP.createServer()
 server.options = ServerOptions(requestSizeLimit: 1000, connectionLimit: 10)
 ```
 */
public struct ServerOptions {

    /// A default limit of 1mb on the size of requests that a server should accept.
    public static let defaultRequestSizeLimit = 1048576

    /// A default limit of 10,000 on the number of concurrent connections that a server should accept.
    public static let defaultConnectionLimit = 10000

    /// Defines a default response to an over-sized request of HTTP 413: Request Too Long. A message is also
    /// logged at debug level.
    public static let defaultRequestSizeResponseGenerator: (Int, String) -> (HTTPStatusCode, String)? = { (limit, clientSource) in
        Log.debug("Request from \(clientSource) exceeds size limit of \(limit) bytes. Connection will be closed.")
        return (.requestTooLong, "")
    }

    /// Defines a default response when refusing a new connection of HTTP 503: Service Unavailable. A message is
    /// also logged at debug level.
    public static let defaultConnectionResponseGenerator: (Int, String) -> (HTTPStatusCode, String)? = { (limit, clientSource) in
        Log.debug("Rejected connection from \(clientSource): Maximum connection limit of \(limit) reached.")
        return (.serviceUnavailable, "")
    }

    /// Defines the maximum size of an incoming request, in bytes. If requests are received that are larger
    /// than this limit, they will be rejected and the connection will be closed.
    ///
    /// A value of `nil` means no limit.
    public let requestSizeLimit: Int?

    /// Defines the maximum number of concurrent connections that a server should accept. Clients attempting
    /// to connect when this limit has been reached will be rejected.
    public let connectionLimit: Int?

    /**
     Determines the response message and HTTP status code used to respond to clients whose request exceeds
     the `requestSizeLimit`. The current limit and client's address are provided as parameters to enable a
     message to be logged, and/or a response to be provided back to the client.

     The returned tuple indicates the HTTP status code and response body to send to the client. If `nil` is
     returned, then no response will be sent.

     Example usage:
     ```
     let oversizeResponse: (Int, String) -> (HTTPStatusCode, String)? = { (limit, client) in
         Log.debug("Rejecting request from \(client): Exceeds limit of \(limit) bytes")
         return (.requestTooLong, "Your request exceeds the limit of \(limit) bytes.\r\n")
     }
     ```
     */
    public let requestSizeResponseGenerator: (Int, String) -> (HTTPStatusCode, String)?

    /**
     Determines the response message and HTTP status code used to respond to clients that attempt to connect
     while the server is already servicing the maximum number of connections, as defined by `connectionLimit`.
     The current limit and client's address are provided as parameters to enable a  message to be logged,
     and/or a response to be provided back to the client.

     The returned tuple indicates the HTTP status code and response body to send to the client. If `nil` is
     returned, then no response will be sent.

     Example usage:
     ```
     let connectionResponse: (Int, String) -> (HTTPStatusCode, String)? = { (limit, client) in
         Log.debug("Rejecting request from \(client): Connection limit \(limit) reached")
         return (.serviceUnavailable, "Service busy - please try again later.\r\n")
     }
     ```
     */
    public let connectionResponseGenerator: (Int, String) -> (HTTPStatusCode, String)?

    /// Create a `ServerOptions` to determine the behaviour of a `Server`.
    ///
    /// - parameter requestSizeLimit: The maximum size of an incoming request. Defaults to `ServerOptions.defaultRequestSizeLimit`.
    /// - parameter connectionLimit: The maximum number of concurrent connections. Defaults to `ServerOptions.defaultConnectionLimit`.
    /// - parameter requestSizeResponseGenerator: A closure producing a response to send to a client when an over-sized request is rejected. Defaults to `ServerOptions.defaultRequestSizeResponseGenerator`.
    /// - parameter defaultConnectionResponseGenerator: A closure producing a response to send to a client when a the server is busy and new connections are not being accepted. Defaults to `ServerOptions.defaultConnectionResponseGenerator`.
    public init(requestSizeLimit: Int? = ServerOptions.defaultRequestSizeLimit,
                connectionLimit: Int? = ServerOptions.defaultConnectionLimit,
                requestSizeResponseGenerator: @escaping (Int, String) -> (HTTPStatusCode, String)? = ServerOptions.defaultRequestSizeResponseGenerator,
                connectionResponseGenerator: @escaping (Int, String) -> (HTTPStatusCode, String)? = ServerOptions.defaultConnectionResponseGenerator)
    {
        self.requestSizeLimit = requestSizeLimit
        self.connectionLimit = connectionLimit
        self.requestSizeResponseGenerator = requestSizeResponseGenerator
        self.connectionResponseGenerator = connectionResponseGenerator
    }

}
