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

public struct ConnectionUpgrader {
    static var instance = ConnectionUpgrader()
    
    private var registry = [String: ConnectionUpgradeFactory]()
    
    public static func register(factory: ConnectionUpgradeFactory) {
        ConnectionUpgrader.instance.registry[factory.name.lowercased()] = factory
    }
    
    static func clear() {
        ConnectionUpgrader.instance.registry.removeAll()
    }
    
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
        
        var notFound = true
        let protocolList = protocols.split(separator: ",")
        for eachProtocol in protocolList {
            let theProtocol = eachProtocol.first?.trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
            if theProtocol.characters.count != 0, let factory = registry[theProtocol.lowercased()] {
                notFound = !factory.upgrade(handler: handler, request: request, response: response)
            }
        }
        
        if notFound {
            do {
                response.statusCode = HTTPStatusCode.notFound
                let message = "None of the protocols specified in the Upgrade header are registered"
                response.headers["Content-Type"] = ["text/plain"]
                response.headers["Content-Length"] = [String(message.characters.count)]
                try response.write(from: message)
                try response.end()
            }
            catch {
                Log.error("Failed to send error response to Upgrade request")
            }
        }
    }
}
