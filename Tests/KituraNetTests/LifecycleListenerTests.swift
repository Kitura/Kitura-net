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

import Dispatch
import Foundation

import XCTest

@testable import KituraNet

class LifecycleListenerTests: KituraNetTest {

    static var allTests : [(String, (LifecycleListenerTests) -> () throws -> Void)] {
        return [
            ("testLifecycle", testLifecycle),
            ("testLifecycleWithState", testLifecycleWithState),
            ("testServerFailLifecycle", testServerFailLifecycle),
            ("testFastCGILifecycle", testFastCGILifecycle)
        ]
    }

    override func setUp() {
        doSetUp()
    }

    override func tearDown() {
        doTearDown()
    }

    func testLifecycle() {
        var started = false
        let startExpectation = self.expectation(description: "start")

        let server = HTTP.createServer()
        server.started {
            started = true
            startExpectation.fulfill()
        }
        
        server.clientConnectionFailed() { error in
            XCTFail("A client connection had an error [\(error)]")
        }

        do {
            try server.listen(on: self.port, address: "localhost")

            self.waitForExpectations(timeout: 5) { error in
                XCTAssertNil(error)
                XCTAssertTrue(started)
                let stopExpectation = self.expectation(description: "stop")

                server.stopped {
                    stopExpectation.fulfill()
                }

                server.stop()

                self.waitForExpectations(timeout: 5) { error in
                    XCTAssertNil(error)
                }
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }
    
    func testFastCGILifecycle() {
        
        //Create server
        let server = FastCGI.createServer()

        //Check initial server state is unknown
        XCTAssertEqual(server.state, ServerState.unknown)

        //Confirm started state is set upon server start
        let startExpectation = self.expectation(description: "start")
        server.started {
            XCTAssertEqual(server.state, ServerState.started)
            startExpectation.fulfill()
        }
        
        do {
            try server.listen(on: self.port, address: "localhost")
            
            self.waitForExpectations(timeout: 5) { error in
                XCTAssertNil(error)
                
                //Confirm stopped state is set upon server stop
                let stopExpectation = self.expectation(description: "stop")
                
                server.stopped {
                    XCTAssertEqual(server.state, ServerState.stopped)
                    stopExpectation.fulfill()
                }
                
                server.stop()
                
                self.waitForExpectations(timeout: 5) { error in
                    XCTAssertNil(error)
                }
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }
    
    func testLifecycleWithState() {
        var started = false
        let startExpectation = self.expectation(description: "start")

        let server = HTTP.createServer()
        server.started {
            startExpectation.fulfill()
        }

        do {
            try server.listen(on: self.port, address: "localhost")

            self.waitForExpectations(timeout: 5) { error in
                XCTAssertNil(error)

                server.started {
                    started = true
                }

                XCTAssertTrue(started)

                server.stop()
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    func testServerFailLifecycle() {

        let failedCallbackExpectation = self.expectation(description: "failedCallback")
        
        let server = HTTP.createServer()
        server.failed(callback: { error in
            failedCallbackExpectation.fulfill()
        })

        do {
            try server.listen(on: -1, address: nil)
        } catch {
            // Do NOT fail the test if an error is thrown.
            // In this test case an error should be thrown.
        }
        
        self.waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
    }
}
