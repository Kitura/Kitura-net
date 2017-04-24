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

class UpgradeTests: KituraNetTest {
    
    static var allTests : [(String, (UpgradeTests) -> () throws -> Void)] {
        return [
            ("testErrorWithStatusCode", testErrorWithStatusCode),
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
    
    func testErrorWithStatusCode() {
        ConnectionUpgrader.clear()
        ConnectionUpgrader.register(factory: TestingProtocolSocketProcessorFactory(statusCode: .notAcceptable))
        
        performServerTest(nil, useSSL: false) { expectation in
            
            guard let socket = self.sendUpgradeRequest(forProtocol: "testing") else { return }
            
            let (rawParser, _) = self.processUpgradeResponse(socket: socket)
            
            guard let parser = rawParser else { return }
            
            XCTAssertEqual(parser.statusCode, HTTPStatusCode.notAcceptable, "Returned status code on upgrade request was \(parser.statusCode) and not \(HTTPStatusCode.notAcceptable)")
            
            expectation.fulfill()
        }
    }
    
    func testNoRegistrations() {
        ConnectionUpgrader.clear()
        
        performServerTest(nil, useSSL: false) { expectation in
            
            guard let socket = self.sendUpgradeRequest(forProtocol: "testing") else { return }

            let (rawParser, _) = self.processUpgradeResponse(socket: socket)

            guard let parser = rawParser else { return }
            
            XCTAssertEqual(parser.statusCode, HTTPStatusCode.notFound, "Returned status code on upgrade request was \(parser.statusCode) and not \(HTTPStatusCode.notFound)")
            
            expectation.fulfill()
        }
    }
    
    func testSuccessfullUpgrade() {
        ConnectionUpgrader.clear()
        
        let closedSocketExpectation = expectation(description: "ClosedSocket callback")
        
        ConnectionUpgrader.register(factory: TestingProtocolSocketProcessorFactory() {
            closedSocketExpectation.fulfill()
        })
        
        performServerTest(nil, useSSL: false) { expectation in
            
            guard let socket = self.sendUpgradeRequest(forProtocol: "testing") else { return }
            
            let (rawParser, _) = self.processUpgradeResponse(socket: socket)
            
            guard let parser = rawParser else { return }
            
            XCTAssertEqual(parser.statusCode, HTTPStatusCode.switchingProtocols, "Returned status code on upgrade request was \(parser.statusCode) and not \(HTTPStatusCode.switchingProtocols)")
            
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
                
                socket.close()
                
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
        
        XCTAssert(ConnectionUpgrader.upgradersExist, "Upgrader factory failed to register")
        
        performServerTest(nil, useSSL: false, asyncTasks: { expectation in
            
            guard let socket = self.sendUpgradeRequest(forProtocol: "testing123") else { return }
            
            let (rawParser, _) = self.processUpgradeResponse(socket: socket)
            
            guard let parser = rawParser else { return }
            
            XCTAssertEqual(parser.statusCode, HTTPStatusCode.notFound, "Returned status code on upgrade request was \(parser.statusCode) and not \(HTTPStatusCode.notFound)")
            
            expectation.fulfill()
        },
        { expectation in
            do {
                let socket = try Socket.create()
                try socket.connect(to: "localhost", port: Int32(self.port))
                
                let request = "GET /test/upgrade HTTP/1.1\r\n" +
                    "Host: localhost:\(self.port)\r\n" +
                    "Connection: Upgrade\r\n" +
                "\r\n"
                
                guard let data = request.data(using: .utf8) else { return }
                
                try socket.write(from: data)
                
                let (rawParser, _) = self.processUpgradeResponse(socket: socket)
                
                guard let parser = rawParser else { return }
                
                XCTAssertEqual(parser.statusCode, HTTPStatusCode.notFound, "Returned status code on upgrade request was \(parser.statusCode) and not \(HTTPStatusCode.notFound)")
                
                expectation.fulfill()
            }
            catch let error {
                XCTFail("Failed to send upgrade request. Error=\(error)")
            }
        })
    }
    
    private func sendUpgradeRequest(forProtocol: String) -> Socket? {
        var socket: Socket?
        do {
            socket = try Socket.create()
            try socket?.connect(to: "localhost", port: Int32(self.port))
            
            let request = "GET /test/upgrade HTTP/1.1\r\n" +
                          "Host: localhost:\(self.port)\r\n" +
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
    
    
    
    private func processUpgradeResponse(socket: Socket) -> (HTTPParser?, NSData?) {
        let parser = HTTPParser(isRequest: false)
        var unparsedData: NSData?
        var errorFlag = false
        
        var keepProcessing = true
        var notFoundEof = true
        let buffer = NSMutableData()
        
        do {
            while keepProcessing {
                buffer.length = 0
                let count = try socket.read(into: buffer)

                if notFoundEof {
                    let bytes = buffer.bytes.assumingMemoryBound(to: Int8.self)
                    let (numberParsed, _) = parser.execute(bytes, length: buffer.length)

                    if parser.completed {
                        keepProcessing = false
                        let bytesLeft = buffer.length - numberParsed
                        if bytesLeft != 0 {
                            unparsedData = NSData(bytes: buffer.bytes+buffer.length-bytesLeft, length: bytesLeft)
                        }
                    }
                    else {
                        notFoundEof = count != 0
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
        return (errorFlag ? nil : parser, unparsedData)
    }
    
    // A very simple `ConnectionUpgradeFactory` class for testing
    class TestingProtocolSocketProcessorFactory: ConnectionUpgradeFactory {
        public var name: String { return "Testing" }
        
        private let statusCode: HTTPStatusCode?
        private let closeCallback: (() -> Void)?
        
        init(statusCode: HTTPStatusCode? = nil, closeCallback: (() -> Void)? = nil) {
            self.statusCode = statusCode
            self.closeCallback = closeCallback
        }
        
        public func upgrade(handler: IncomingSocketHandler, request: ServerRequest, response: ServerResponse) -> (IncomingSocketProcessor?, String?) {
            if let statusCode = statusCode {
                response.statusCode = statusCode
                return (nil, "Response status code set to \(HTTP.statusCodes[statusCode.rawValue] ?? "Unknown").")
            }
            else {
                return (TestingSocketProcessor(closeCallback: closeCallback), nil)
            }
        }
    }
    
    // A very simple `IncomingSocketProcessor` for testing.
    class TestingSocketProcessor: IncomingSocketProcessor {
        public weak var handler: IncomingSocketHandler?
        public var keepAliveUntil: TimeInterval = 0.0
        public var inProgress = true
        
        private let closeCallback: (() -> Void)?
        
        init(closeCallback: (() -> Void)? = nil) {
            self.closeCallback = closeCallback
        }
        
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
        
        public func socketClosed() {
            closeCallback?()
        }
    }
}
