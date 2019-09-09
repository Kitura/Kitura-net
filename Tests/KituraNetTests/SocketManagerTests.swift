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

class SocketManagerTests: KituraNetTest {
    
    static var allTests : [(String, (SocketManagerTests) -> () throws -> Void)] {
        return [
            ("testHandlerCleanup", testHandlerCleanup)        ]
    }
    
    var manager: IncomingSocketManager?
    
    override func setUp() {
        manager = IncomingSocketManager()
    }
    
    override func tearDown() {
        #if !GCD_ASYNCH && os(Linux)
            if let manager = manager {
                manager.stop()
                usleep(UInt32(manager.epollTimeout) * UInt32(1000))  /* epollTimeout is in milliseconds */
            }
        #endif
    }
    
    func testHandlerCleanup() {
        guard let manager = manager else {
            XCTFail("Failed to create an IncomingSocketManager.")
            return
        }
        
        do {
            let socket1 = try Socket.create()
            let socket2 = try Socket.create()
            let socket3 = try Socket.create()

            // Sleep momentarily after creating sockets before creating any read events.
            // For an unknown reason, with GCD_ASYNCH on Linux, a read event fires if a
            // Dispatch reader source is set up on the socket's fd too soon, even though
            // the socket is not connected, and this causes us to remove the socket and
            // fail the test.
            usleep(10000)

            let processor1 = TestIncomingSocketProcessor()
            manager.handle(socket: socket1, processor: processor1)
            XCTAssertEqual(manager.socketHandlerCount, 1, "There should be 1 IncomingSocketHandler, there are \(manager.socketHandlerCount)")
            
            // The check for idle sockets to clean up happens when new sockets arrive.
            // However the check is done at most once a minute. To avoid waiting a minute
            // and only then simulating a new incoming socket, this test first sets the
            // last time the check for idle sockets to two minutes in the past.
            manager.keepAliveIdleLastTimeChecked = Date().addingTimeInterval(-120.0)
            
            let processor2 = TestIncomingSocketProcessor()
            manager.handle(socket: socket2, processor: processor2)
            XCTAssertEqual(manager.socketHandlerCount, 2, "There should be 2 IncomingSocketHandler, there are \(manager.socketHandlerCount)")

            // Enable cleanup the next time there is a "new incoming socket" (see description above)
            manager.keepAliveIdleLastTimeChecked = Date().addingTimeInterval(-120.0)
            // Mark a processor as NOT in progress, with a keep alive of four minutes from now
            processor1.inProgress = false
            processor1.keepAliveUntil = Date().timeIntervalSinceReferenceDate + 240.0
            
            let processor3 = TestIncomingSocketProcessor()
            manager.handle(socket: socket3, processor: processor3)
            XCTAssertEqual(manager.socketHandlerCount, 3, "There should be 3 IncomingSocketHandler, there are \(manager.socketHandlerCount)")
            
            // Enable cleanup the next time there is a "new incoming socket" (see description above)
            manager.keepAliveIdleLastTimeChecked = Date().addingTimeInterval(-120.0)
            // Mark a processor as NOT in progress, with no keep alive
            processor2.inProgress = false
            
            let socket4 = try Socket.create()
            let processor4 = TestIncomingSocketProcessor()
            manager.handle(socket: socket4, processor: processor4)
            XCTAssertEqual(manager.socketHandlerCount, 3, "There should be 3 IncomingSocketHandler, there are \(manager.socketHandlerCount)")
        }
        catch let error {
            XCTFail("Failed to create a socket. Error=\(error)")
        }
    }
}
