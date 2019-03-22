/**
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
 **/

import Foundation
import Dispatch
import LoggerAPI

import XCTest

@testable import KituraNet
import Socket

class UnixSocketTests: KituraNetTest {

    static var allTests : [(String, (UnixSocketTests) -> () throws -> Void)] {
        return [
            ("testUnixSockets", testUnixSockets),
        ]
    }

    override func setUp() {
        doSetUp()
        // Create a file for Unix socket tests
        socketFilePath = "/tmp/KituraNetTests.testUnixSockets.\(UUID())"
        print("Socket file path = \(socketFilePath)")
        let fm = FileManager.default
        if !fm.createFile(atPath: socketFilePath, contents: Data()) {
            XCTFail("Failed to create file \(socketFilePath)")
        }
    }

    override func tearDown() {
        doTearDown()
        // Clean up temporary file
        let fileURL = URL(fileURLWithPath: socketFilePath)
        let fm = FileManager.default
        do {
            try fm.removeItem(at: fileURL)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    // Socket file path for Unix socket tests
    private var socketFilePath: String = ""

    let unixDelegate = TestUnixSocketServerDelegate()

    /// Test that we can start a server on a Unix socket, and then make a ClientRequest
    /// to that socket. The TestUnixSocketServerDelegate.handle() function will verify
    /// that the incoming request's socket is a unix socket.
    func testUnixSockets() {
        performServerTest(unixDelegate, socketPath: socketFilePath) { expectation in
            self.performRequest("get", path: "/banana", socketPath: self.socketFilePath, callback: { response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .OK was \(String(describing: response?.statusCode))")
                expectation.fulfill()
            })
        }
    }

    class TestUnixSocketServerDelegate: ServerDelegate {
        func handle(request: ServerRequest, response: ServerResponse) {
            guard let request = request as? HTTPServerRequest else {
                return XCTFail("Request was not an HTTPServerRequest")
            }
            guard let socketSignature = request.socketSignature else {
                return XCTFail("Socket signature missing")
            }
            XCTAssertEqual(socketSignature.protocolFamily, Socket.ProtocolFamily.unix, "Socket was not a Unix socket")
            XCTAssertEqual(request.method.lowercased(), "get")
            response.statusCode = .OK
            do {
                try response.end(text: "OK")
            } catch {
                XCTFail("Error sending response: \(error)")
            }
        }
    }

}
