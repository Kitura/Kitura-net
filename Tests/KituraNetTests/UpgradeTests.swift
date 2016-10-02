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

class UpgradeTests: XCTestCase {
    
    static var allTests : [(String, (UpgradeTests) -> () throws -> Void)] {
        return [
            ("testNoRegistrations", testNoRegistrations)
        ]
    }
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    func testNoRegistrations() {
        //performServerTest(TestServerDelegate()) { expectation in
        //    guard let socket = self.sendUpgradeRequest() else { return }
        //
        //    guard let response = self.processUpgradeResponse(socket: socket) else { return }
        //
        //}
    }
    
    private func sendUpgradeRequest() -> Socket? {
        var socket: Socket?
        do {
            socket = try Socket.create()
            try socket?.connect(to: "localhost", port: 8090)
            
            let request = "GET /test/upgrade HTTP/1.1\r\n" +
                          "Host: localhost:8090\r\n" +
                          "Upgrade: testing\r\n" +
                          "Connection: Upgrade\r\n" +
                          "\r\n"
            
            guard let data = request.data(using: .utf8) else { return nil }
            
            try socket?.write(from: data)
        }
        catch let error {
            socket = nil
            XCTFail("Failed to send upgrade request. Error=\(error)")
        }
        return socket
    }
    
    private func processUpgradeResponse(socket: Socket) -> HTTPIncomingMessage? {
        var response: HTTPIncomingMessage? = HTTPIncomingMessage(isRequest: false)
        
        var keepProcessing = true
        let buffer = NSMutableData()
        
        do {
            while keepProcessing {
                buffer.length = 0
                let count = try socket.read(into: buffer)
                if count != 0 {
                    
                }
                else {
                    
                }
            }
        }
        catch let error {
            response = nil
            XCTFail("Failed to send upgrade request. Error=\(error)")
        }
        return response
    }
    
    class TestServerDelegate : ServerDelegate {
        
        func handle(request: ServerRequest, response: ServerResponse) {
            XCTFail("Server deelgate invoked in an Upgrade scenario")
        }
    }
}
