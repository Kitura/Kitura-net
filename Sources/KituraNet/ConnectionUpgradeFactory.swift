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

import Foundation

/// A class to create new `IncomingSocketProcessor`s for upgraded connections. These factory classes are invoked
/// when an "upgrade" HTTP request comes to the server for a particular protocol.
public protocol ConnectionUpgradeFactory {
    /// The name of the protocol supported by this `ConnectionUpgradeFactory`. A case insensitive compare is made with this name.
    var name: String { get }
    
    /// "Upgrade" a connection to the protocol supported by this `ConnectionUpgradeFactory`.
    ///
    /// - Parameter handler: The `IncomingSocketHandler` that is handling the connection being upgraded.
    /// - Parameter request: The `ServerRequest` object of the incoming "upgrade" request.
    /// - Parameter response: The `ServerResponse` object that will be used to send the response of the "upgrade" request.
    ///
    /// - Returns: A tuple of the created `IncomingSocketProcessor` and a message to send as the body of the response to
    ///           the upgrade request. The `IncomingSocketProcessor` should be nil if the upgrade request wasn't successful.
    ///           If the message is nil, the response will not contain a body.
    ///
    /// - Note: The `ConnectionUpgradeFactory` instance doesn't need to work with the `ServerResponse` unless it
    ///        needs to add special headers to the response.
    func upgrade(handler: IncomingSocketHandler, request: ServerRequest, response: ServerResponse) -> (IncomingSocketProcessor?, String?)
}
