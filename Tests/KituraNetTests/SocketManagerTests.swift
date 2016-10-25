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

import Foundation

import XCTest

@testable import KituraNet
import Socket

class SocketManagerTests: XCTestCase {
    
    static var allTests : [(String, (SocketManagerTests) -> () throws -> Void)] {
        return [
            ("testHandlerCleanup", testHandlerCleanup)        ]
    }
    
    func testHandlerCleanup() {
        do {
            let manager = IncomingSocketManager()
            
            let socket1 = try Socket.create()
            let processor1 = TestIncomingSocketProcessor()
            manager.handle(socket: socket1, processor: processor1)
            XCTAssertEqual(manager.socketHandlers.count, 1, "There should be 1 IncomingSocketHandler, there are \(manager.socketHandlers.count)")
            
            // The check for idle sockets to clean up happens when new sockets arrive.
            // However the check is done at most once a minute. To avoid waiting a minute
            // and only then simulating a new incoming socket, this test first sets the
            // last time the check for idle sockets to two minutes in the past.
            manager.keepAliveIdleLastTimeChecked = Date().addingTimeInterval(-120.0)
            
            let socket2 = try Socket.create()
            let processor2 = TestIncomingSocketProcessor()
            manager.handle(socket: socket2, processor: processor2)
            XCTAssertEqual(manager.socketHandlers.count, 2, "There should be 2 IncomingSocketHandler, there are \(manager.socketHandlers.count)")

            // Enable cleanup the next time there is a "new incoming socket" (see description above)
            manager.keepAliveIdleLastTimeChecked = Date().addingTimeInterval(-120.0)
            // Mark a processor as NOT in progress, with a keep alive of four minutes from now
            processor1.inProgress = false
            processor1.keepAliveUntil = Date().timeIntervalSinceReferenceDate + 240.0
            
            let socket3 = try Socket.create()
            let processor3 = TestIncomingSocketProcessor()
            manager.handle(socket: socket3, processor: processor3)
            XCTAssertEqual(manager.socketHandlers.count, 3, "There should be 3 IncomingSocketHandler, there are \(manager.socketHandlers.count)")
            
            // Enable cleanup the next time there is a "new incoming socket" (see description above)
            manager.keepAliveIdleLastTimeChecked = Date().addingTimeInterval(-120.0)
            // Mark a processor as NOT in progress, with no keep alive
            processor2.inProgress = false
            
            let socket4 = try Socket.create()
            let processor4 = TestIncomingSocketProcessor()
            manager.handle(socket: socket4, processor: processor4)
            XCTAssertEqual(manager.socketHandlers.count, 3, "There should be 3 IncomingSocketHandler, there are \(manager.socketHandlers.count)")
        }
        catch let error {
            XCTFail("Failed to create a socket. Error=\(error)")
        }
    }
}
