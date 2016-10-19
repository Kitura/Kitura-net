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

let messageToProtocol = [0x04, 0xa0, 0xb0, 0xc0, 0xd0]
let messageFromProtocol = [0x10, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f]

class UpgradeTests: XCTestCase {
    
    static var allTests : [(String, (UpgradeTests) -> () throws -> Void)] {
        return [
            ("testNoRegistrations", testNoRegistrations),
            ("testSuccessfullUpgrade", testSuccessfullUpgrade),
            ("testWrongRegistration", testWrongRegistration)
        ]
    }
    
    
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    func testNoRegistrations() {
        ConnectionUpgrader.clear()
        
        performServerTest(TestServerDelegate()) { expectation in
            
            guard let socket = self.sendUpgradeRequest(forProtocol: "testing") else { return }

            let (rawResponse, _) = self.processUpgradeResponse(socket: socket)

            guard let response = rawResponse else { return }
            
            XCTAssertEqual(response.httpStatusCode, HTTPStatusCode.notFound, "Returned status code on upgrade request was \(response.httpStatusCode) and not \(HTTPStatusCode.notFound)")
            
            expectation.fulfill()
        }
    }
    
    func testSuccessfullUpgrade() {
        ConnectionUpgrader.clear()
        ConnectionUpgrader.register(factory: TestingProtocolSocketProcessorFactory())
        
        performServerTest(TestServerDelegate()) { expectation in
            
            guard let socket = self.sendUpgradeRequest(forProtocol: "testing") else { return }
            
            let (rawResponse, _) = self.processUpgradeResponse(socket: socket)
            
            guard let response = rawResponse else { return }
            
            XCTAssertEqual(response.httpStatusCode, HTTPStatusCode.switchingProtocols, "Returned status code on upgrade request was \(response.httpStatusCode) and not \(HTTPStatusCode.switchingProtocols)")
            
            do {
                try socket.write(from: NSData(bytes: messageToProtocol, length: messageToProtocol.count))
            }
            catch {
                XCTFail("Failed to send message to TestingProtocol. Error=\(error)")
            }
            
            do {
                let buffer = NSMutableData()
                let bytesRead = try socket.read(into: buffer)
                
                XCTAssertEqual(bytesRead, messageFromProtocol.count, "Message sent by testing protocol wasn't the correct length")
                
                expectation.fulfill()
            }
            catch {
                XCTFail("Failed to send message to TestingProtocol. Error=\(error)")
            }
        }
    }
    
    func testWrongRegistration() {
        ConnectionUpgrader.clear()
        ConnectionUpgrader.register(factory: TestingProtocolSocketProcessorFactory())
        
        performServerTest(TestServerDelegate()) { expectation in
            
            guard let socket = self.sendUpgradeRequest(forProtocol: "testing123") else { return }
            
            let (rawResponse, _) = self.processUpgradeResponse(socket: socket)
            
            guard let response = rawResponse else { return }
            
            XCTAssertEqual(response.httpStatusCode, HTTPStatusCode.notFound, "Returned status code on upgrade request was \(response.httpStatusCode) and not \(HTTPStatusCode.notFound)")
            
            expectation.fulfill()
        }
    }
    
    private func sendUpgradeRequest(forProtocol: String) -> Socket? {
        var socket: Socket?
        do {
            socket = try Socket.create()
            try socket?.connect(to: "localhost", port: 8090)
            
            let request = "GET /test/upgrade HTTP/1.1\r\n" +
                          "Host: localhost:8090\r\n" +
                          "Upgrade: " + forProtocol + "\r\n" +
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
    
    
    
    private func processUpgradeResponse(socket: Socket) -> (HTTPIncomingMessage?, NSData?) {
        let response: HTTPIncomingMessage = HTTPIncomingMessage(isRequest: false)
        var unparsedData: NSData?
        var errorFlag = false
        
        var keepProcessing = true
        let buffer = NSMutableData()
        
        do {
            while keepProcessing {
                buffer.length = 0
                let count = try socket.read(into: buffer)

                if count != 0 {
                    let parserStatus = response.parse(buffer)

                    if parserStatus.state == .messageComplete {
                        keepProcessing = false
                        if parserStatus.bytesLeft != 0 {
                            unparsedData = NSData(bytes: buffer.bytes+buffer.length-parserStatus.bytesLeft, length: parserStatus.bytesLeft)
                        }
                    }
                }
                else {
                    keepProcessing = false
                    errorFlag = true
                    XCTFail("Server closed socket prematurely")
                }
            }
        }
        catch let error {
            errorFlag = true
            XCTFail("Failed to send upgrade request. Error=\(error)")
        }
        return (errorFlag ? nil : response, unparsedData)
    }
    
    class TestServerDelegate : ServerDelegate {
        
        func handle(request: ServerRequest, response: ServerResponse) {
            XCTFail("Server deelgate invoked in an Upgrade scenario")
        }
    }
    
    // A very simple `ConnectionUpgradeFactory` class for testing
    class TestingProtocolSocketProcessorFactory: ConnectionUpgradeFactory {
        public var name: String { return "Testing" }
        
        public func upgrade(handler: IncomingSocketHandler, request: ServerRequest, response: ServerResponse) -> (IncomingSocketProcessor?, String?) {
            return (TestingSocketProcessor(), nil)
        }
    }
    
    // A very simple `IncomingSocketProcessor` for testing.
    class TestingSocketProcessor: IncomingSocketProcessor {
        public weak var handler: IncomingSocketHandler?
        public var keepAliveUntil: TimeInterval = 0.0
        public var inProgress = true
        
        public func process(_ buffer: NSData) -> Bool {
            XCTAssertEqual(buffer.length, messageToProtocol.count, "Message received by testing protocol wasn't the correct length")
            write(from: NSData(bytes: messageFromProtocol, length: messageFromProtocol.count))
            return true
        }
        
        public func write(from data: NSData) {
            handler?.write(from: data)
        }
        
        public func write(from bytes: UnsafeRawPointer, length: Int) {
            handler?.write(from: bytes, length: length)
        }
    
        public func close() {
            handler?.prepareToClose()
        }
    }
}
