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

import LoggerAPI

/// The struct that manages the process of upgrading connections from HTTP 1.1 to other protocols.
///
///  - Note: There a single instance of this struct in a server.
public struct ConnectionUpgrader {
    static var instance = ConnectionUpgrader()
    
    private var registry = [String: ConnectionUpgradeFactory]()
    
    /// Register a `ConnectionUpgradeFactory` class instances used to create appropriate `IncomingSocketProcessor`s
    /// for upgraded conections
    ///
    /// - Parameter factory: The `ConnectionUpgradeFactory` class instance being registered.
    public static func register(factory: ConnectionUpgradeFactory) {
        ConnectionUpgrader.instance.registry[factory.name.lowercased()] = factory
    }
    
    /// Clear the `ConnectionUpgradeFactory` registry. Used in testing.
    static func clear() {
        ConnectionUpgrader.instance.registry.removeAll()
    }
    
    /// The function that performs the upgrade.
    ///
    /// - Parameter handler: The `IncomingSocketHandler` that is handling the connection being upgraded.
    /// - Parameter request: The `ServerRequest` object of the incoming "upgrade" request.
    /// - Parameter response: The `ServerResponse` object that will be used to send the response of the "upgrade" request.
    func upgradeConnection(handler: IncomingSocketHandler, request: ServerRequest, response: ServerResponse) {
        guard let protocols = request.headers["Upgrade"] else {
            do {
                response.statusCode = HTTPStatusCode.badRequest
                try response.write(from: "No protocol specified in the Upgrade header")
                try response.end()
            }
            catch {
                Log.error("Failed to send error response to Upgrade request")
            }
            return
        }
        
        var oldProcessor: IncomingSocketProcessor?
        var processor: IncomingSocketProcessor?
        var responseBody: String?
        var notFound = true
        let protocolList = protocols.split(separator: ",")
        var protocolName: String?
        for eachProtocol in protocolList {
            let theProtocol = eachProtocol.first?.trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
            if theProtocol.characters.count != 0, let factory = registry[theProtocol.lowercased()] {
                (processor, responseBody) = factory.upgrade(handler: handler, request: request, response: response)
                protocolName = theProtocol
                notFound = false
                break
            }
        }
        
        do {
            if notFound {
                response.statusCode = HTTPStatusCode.notFound
                let message = "None of the protocols specified in the Upgrade header are registered"
                response.headers["Content-Type"] = ["text/plain"]
                response.headers["Content-Length"] = [String(message.characters.count)]
                try response.write(from: message)
            }
            else {
                if let theProcessor = processor, let theProtocolName = protocolName {
                    response.statusCode = .switchingProtocols
                    response.headers["Upgrade"] = [theProtocolName]
                    response.headers["Connection"] = ["Upgrade"]
                    oldProcessor = handler.processor
                    theProcessor.handler = handler
                    handler.processor = theProcessor
                    oldProcessor?.inProgress = false
                }
                else {
                    response.statusCode = .badRequest
                }
                if let theBody = responseBody {
                    try response.write(from: theBody)
                }
            }
            try response.end()
        }
        catch {
            Log.error("Failed to send response to Upgrade request")
        }
    }
}
