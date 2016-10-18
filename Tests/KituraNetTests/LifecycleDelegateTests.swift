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

class LifecycleDelegateTests: XCTestCase {

    static var allTests : [(String, (LifecycleDelegateTests) -> () throws -> Void)] {
        return [
            ("testLifecycle", testLifecycle)
        ]
    }

    override func setUp() {
        doSetUp()
    }

    override func tearDown() {
        doTearDown()
    }

    private let delegate = TestServerDelegate()
    var started = false
    var finished = false

    func testLifecycle() {

        performServerTest(delegate, lifecycleDelegate: self, asyncTasks: { expectation in
            self.performRequest("get", path: "/any", callback: { response in
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
                XCTAssertTrue(self.started, "server delegate serverStarted:on: wasn't called")
                expectation.fulfill()
            })
        })

        sleep(1)
        XCTAssertTrue(self.finished, "server delegate serverStopped:on: wasn't called")
    }

    private class TestServerDelegate : ServerDelegate {

        func handle(request: ServerRequest, response: ServerResponse) {
                handleGet(request: request, response: response)

        }

        func handleGet(request: ServerRequest, response: ServerResponse) {
            let payload = "hello"
            let payloadData = payload.data(using: .utf8)!
            do {
                response.headers["Content-Length"] = ["\(payloadData.count)"]
                try response.write(from: payloadData)
                try response.end()
            }
            catch {
                print("Error writing response.")
            }
        }
    }
}

extension LifecycleDelegateTests: ServerLifecycleDelegate {

    func serverStarted(_ server: Server, on port: Int) {
        print("[Lifecycle started]")
        self.started = true
    }

    func serverStopped(_ server: Server, on port: Int) {
        print("[Lifecycle stopped]")
        self.finished = true
    }
}
