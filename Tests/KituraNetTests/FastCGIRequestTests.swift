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

import XCTest
@testable import KituraNet
import Foundation
import Socket

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

class FastCGIRequestTests: KituraNetTest {
    
    // All tests
    //
    static var allTests : [(String, (FastCGIRequestTests) -> () throws -> Void)] {
        return [
            ("testInvalidParameter", testInvalidParameter),
            ("testInvalidProtocolVersion", testInvalidProtocolVersion),
            ("testInvalidRole", testInvalidRole),
            ("testSimpleRequest", testSimpleRequest),
            ("testTwoBeginRequests", testTwoBeginRequests)
        ]
    }
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    func testInvalidParameter() {
        performFastCGIServerTest(TestDelegate()) { expectation in
            do {
                let socket = try Socket.create()
                try socket.connect(to: "localhost", port: Int32(self.port))
                
                let message = NSMutableData()
                let requestId = self.addBeginRequest(to: message)
                
                // Add a Parameters record with a zero byte name
                var bytes = [UInt8](repeating: 0, count: 8)
                bytes[0] = 1       // FastCGI protocol version
                bytes[1] = 4       // PARAMS
                self.copyUInt16IntoBuffer(&bytes, offset: 2, value: UInt16(requestId))
                let parameterBuffer = NSMutableData()
                self.addNameValuePair(to: parameterBuffer, name: "", value: "HTTP")
                self.copyUInt16IntoBuffer(&bytes, offset: 4, value: UInt16(parameterBuffer.length))
                message.append(&bytes, length: bytes.count)
                message.append(parameterBuffer.bytes, length: parameterBuffer.length)
                
                
                try socket.write(from: message)
                
                self.validateResultRecord(from: socket, canBeClosedPrematurely: true, expectation: expectation)
                
                expectation.fulfill()
                
                socket.close()
            }
            catch {
                XCTFail("Failed to send the FastCGI Request. Error=\(error)")
            }
        }
    }
    
    func testInvalidProtocolVersion() {
        performFastCGIServerTest(TestDelegate()) { expectation in
            do {
                let socket = try Socket.create()
                try socket.connect(to: "localhost", port: Int32(self.port))
                
                let message = NSMutableData()
                _ = self.addBeginRequest(to: message, protocolVersion: 100)
                
                try socket.write(from: message)
                
                self.validateResultRecord(from: socket, canBeClosedPrematurely: true, expectation: expectation)
                
                expectation.fulfill()
                
                socket.close()
            }
            catch {
                XCTFail("Failed to send the FastCGI Request. Error=\(error)")
            }
        }
    }
    
    func testInvalidRole() {
        performFastCGIServerTest(TestDelegate()) { expectation in
            do {
                let socket = try Socket.create()
                try socket.connect(to: "localhost", port: Int32(self.port))
                
                let message = NSMutableData()
                _ = self.addBeginRequest(to: message, role: 100)
                
                try socket.write(from: message)
                
                self.validateResultRecord(from: socket, canBeClosedPrematurely: true, expectation: expectation)
                
                expectation.fulfill()
                
                socket.close()
            }
            catch {
                XCTFail("Failed to send the FastCGI Request. Error=\(error)")
            }
        }
    }
    
    func testSimpleRequest() {
        performFastCGIServerTest(TestDelegate()) { expectation in
            do {
                let socket = try Socket.create()
                try socket.connect(to: "localhost", port: Int32(self.port))
                
                let message = NSMutableData()
                let requestId = self.addBeginRequest(to: message)
                self.addParameters(to: message, requestId: requestId)
                self.addStdIn(to: message, requestId: requestId)
                
                try socket.write(from: message)
                
                usleep(10000)
                
                expectation.fulfill()
                
                socket.close()
            }
            catch {
                XCTFail("Failed to send the FastCGI Request. Error=\(error)")
            }
        }
    }
    
    func testTwoBeginRequests() {
        performFastCGIServerTest(TestDelegate()) { expectation in
            do {
                let socket = try Socket.create()
                try socket.connect(to: "localhost", port: Int32(self.port))
                
                let message = NSMutableData()
                let requestId = self.addBeginRequest(to: message)
                _ = self.addBeginRequest(to: message, requestId: requestId)
                
                try socket.write(from: message)
                
                self.validateResultRecord(from: socket, canBeClosedPrematurely: true, expectation: expectation)
                
                usleep(10000)
                
                expectation.fulfill()
                
                socket.close()
            }
            catch {
                XCTFail("Failed to send the FastCGI Request. Error=\(error)")
            }
        }
    }
    
    private func addBeginRequest(to: NSMutableData, requestId: Int=#line, protocolVersion: Int=1, role: Int=1) -> Int{
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8(protocolVersion)  // FastCGI protocol version
        bytes[1] = 1                       // BEGIN_REQUEST
        
        copyUInt16IntoBuffer(&bytes, offset: 2, value: UInt16(requestId))
        
        copyUInt16IntoBuffer(&bytes, offset: 4, value: UInt16(8))
        
        copyUInt16IntoBuffer(&bytes, offset: 8, value: UInt16(role))
        
        to.append(&bytes, length: bytes.count)
        
        return requestId
    }
    
    private func addParameters(to: NSMutableData, requestId: Int) {
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 1       // FastCGI protocol version
        bytes[1] = 4       // PARAMS
        
        copyUInt16IntoBuffer(&bytes, offset: 2, value: UInt16(requestId))
        
        let parameterBuffer = NSMutableData()
        addNameValuePair(to: parameterBuffer, name: "REQUEST_SCHEME", value: "HTTP")
        addNameValuePair(to: parameterBuffer, name: "HTTP_HOST", value: "localhost:\(self.port)")
        addNameValuePair(to: parameterBuffer, name: "REQUEST_METHOD", value: "GET")
        addNameValuePair(to: parameterBuffer, name: "REQUEST_URI", value: "/hello")
        addNameValuePair(to: parameterBuffer, name: "SERVER_PROTOCOL", value: "HTTP/1.1")
        addNameValuePair(to: parameterBuffer, name: "REMOTE_ADDR", value: "localhost")
        
        copyUInt16IntoBuffer(&bytes, offset: 4, value: UInt16(parameterBuffer.length))
        
        to.append(&bytes, length: bytes.count)
        
        to.append(parameterBuffer.bytes, length: parameterBuffer.length)
        
        copyUInt16IntoBuffer(&bytes, offset: 4, value: 0)
        
        to.append(&bytes, length: bytes.count)
    }
    
    private func addStdIn(to: NSMutableData, requestId: Int) {
        var bytes = [UInt8](repeating: 0, count: 8)
        bytes[0] = 1       // FastCGI protocol version
        bytes[1] = 5       // STDIN
        
        copyUInt16IntoBuffer(&bytes, offset: 2, value: UInt16(requestId))
        
        copyUInt16IntoBuffer(&bytes, offset: 4, value: 0)
        
        to.append(&bytes, length: bytes.count)
    }
    
    private func validateResultRecord(from: Socket, canBeClosedPrematurely: Bool, expectation: XCTestExpectation) {
        let buffer = NSMutableData()
        var notFinished = true
        
        do {
            // Read in a record header
            while notFinished && buffer.length < 8 {
                let count = try from.read(into: buffer)
                
                if count != 0 {
                    print("---> Buffer: \(buffer)")
                }
                else {
                    notFinished = false
                    if !canBeClosedPrematurely {
                        XCTFail("Server closed socket prematurely")
                    }
                }
            }
        }
        catch let error {
            XCTFail("Failed to send upgrade request. Error=\(error)")
        }
    }
    
    private func addNameValuePair(to: NSMutableData, name: String, value: String) {
        var bytes: [UInt8] = [0,0,0,0]
        
        let nameCount = name.utf8.count
        let valueCount = value.utf8.count
        
        // Copy length of name into the buffer
        bytes[0] = UInt8(nameCount)
        to.append(&bytes, length: 1)
        
        // Copy length of value into the buffer
        copyUInt32IntoBuffer(&bytes, offset: 0, value: UInt32(valueCount))
        bytes[0] |= 0x80
        to.append(&bytes, length: bytes.count)
        
        // Convert and copy the name into the buffer
        var bufferLength = nameCount+1 // Allow space for null terminator
        var utf8: [CChar] = Array<CChar>(repeating: 0, count: bufferLength)
        _ = name.getCString(&utf8, maxLength: bufferLength, encoding: .utf8)
        to.append(&utf8, length: nameCount)
        
        // Convert and copy the length into the buffer
        bufferLength = valueCount+1 // Allow space for null terminator
        utf8 = Array<CChar>(repeating: 0, count: bufferLength)
        _ = value.getCString(&utf8, maxLength: bufferLength, encoding: .utf8)
        to.append(&utf8, length: valueCount)
    }
    
    private func copyUInt16IntoBuffer(_ bytes: inout [UInt8], offset: Int, value: UInt16) {
        var valueNetworkByteOrder: UInt16
        #if os(Linux)
            valueNetworkByteOrder = Glibc.htons(value)
        #else
            valueNetworkByteOrder = CFSwapInt16HostToBig(value)
        #endif
        let asBytes = UnsafeMutablePointer(&valueNetworkByteOrder)
#if swift(>=4.2)
        (UnsafeMutableRawPointer(mutating: bytes)+offset).copyMemory(from: asBytes, byteCount: 2)
#else
        (UnsafeMutableRawPointer(mutating: bytes)+offset).copyBytes(from: asBytes, count: 2)
#endif
    }
    
    private func copyUInt32IntoBuffer(_ bytes: inout [UInt8], offset: Int, value: UInt32) {
        var valueNetworkByteOrder: UInt32
        #if os(Linux)
            valueNetworkByteOrder = Glibc.htonl(value)
        #else
            valueNetworkByteOrder = CFSwapInt32HostToBig(value)
        #endif
        let asBytes = UnsafeMutablePointer(&valueNetworkByteOrder)
#if swift(>=4.2)
        (UnsafeMutableRawPointer(mutating: bytes)+offset).copyMemory(from: asBytes, byteCount: 4)
#else
        (UnsafeMutableRawPointer(mutating: bytes)+offset).copyBytes(from: asBytes, count: 4)
#endif
    }

    class TestDelegate : ServerDelegate {
        
        func handle(request: ServerRequest, response: ServerResponse) {
            XCTAssertEqual(request.urlURL.scheme, "HTTP", "Expected a scheme of HTTP, it was \(String(describing: request.urlURL.scheme))")
            XCTAssertEqual(request.urlURL.port, KituraNetTest.portDefault)
            XCTAssertEqual(request.urlURL.path, "/hello", "Expected a path of /hello, it was \(request.urlURL.path)")
            XCTAssertEqual(request.url, "/hello".data(using: .utf8))
            do {
                response.statusCode = .OK
                let result = "OK"
                response.headers["Content-Type"] = ["text/plain"]
                response.headers["Content-Length"] = ["\(result.count)"]
                
                try response.end(text: result)
            }
            catch {
                print("Error reading body or writing response")
            }
        }
    }
}
