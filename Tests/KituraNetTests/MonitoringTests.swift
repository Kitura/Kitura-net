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

class MonitoringTests: KituraNetTest {
    
    static var allTests : [(String, (MonitoringTests) -> () throws -> Void)] {
        return [
            ("testStartedFinishedHTTP", testStartedFinishedHTTP)
        ]
    }
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    func testStartedFinishedHTTP() {
        let startedExpectation = self.expectation(description: "started")
        let finishedExpectation = self.expectation(description: "finished")

        Monitor.delegate = TestMonitor(startedExpectation: startedExpectation,
                                       finishedExpectation: finishedExpectation)

        let server = HTTP.createServer()
        server.delegate = TestServerDelegate()
        if KituraNetTest.useSSLDefault {
            server.sslConfig = KituraNetTest.sslConfig
        }

        server.started {
            DispatchQueue.global().async {
                self.performRequest("get", path: "/plover", callback: { response in
                    XCTAssertNotNil(response, "Received a nil response")
                    XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                })
            }
        }
        
        server.failed { error in
            XCTFail("Server failed to start: \(error)")
        }
        
        do {
            try server.listen(on: self.port, address: nil)
        
            self.waitForExpectations(timeout: 10) { error in
                server.stop()
                XCTAssertNil(error);
                Monitor.delegate = nil
            }
        } catch let error {
            XCTFail("Error: \(error)")
            server.stop()
            Monitor.delegate = nil
        }
    }
    
    private class TestMonitor: ServerMonitor {
        private let startedExpectation: XCTestExpectation
        private let finishedExpectation: XCTestExpectation
        private var startedTime = Date()
        
        init(startedExpectation: XCTestExpectation, finishedExpectation: XCTestExpectation) {
            self.startedExpectation = startedExpectation
            self.finishedExpectation = finishedExpectation
        }
        
        public func started(request: ServerRequest, response: ServerResponse) {
            startedTime = Date()
            startedExpectation.fulfill()
        }
        
        public func finished(request: ServerRequest?, response: ServerResponse) {
            let now = Date()
            if now >= startedTime {
                finishedExpectation.fulfill()
            }
            else {
                XCTFail("Monitoring finished called before Monitoring started")
            }
        }
    }
    
    private class TestServerDelegate : ServerDelegate {
        
        func handle(request: ServerRequest, response: ServerResponse) {
            let payloadData = contentTypesString.data(using: .utf8)!
            do {
                response.statusCode = .OK
                response.headers["Content-Length"] = ["\(payloadData.count)"]
                try response.write(from: payloadData)
                try response.end()
            }
            catch {
                XCTFail("Error writing response.")
            }
        }
    }
}
