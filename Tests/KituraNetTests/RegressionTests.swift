/**
 * Copyright IBM Corporation 2017
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

import XCTest

@testable import KituraNet
import Socket
import SSLService

class RegressionTests: KituraNetTest {
    
    static var allTests : [(String, (RegressionTests) -> () throws -> Void)] {
        return [
            ("testIssue1143", testIssue1143),
            ("testServersCollidingOnPort", testServersCollidingOnPort),
            ("testServersSharingPort", testServersSharingPort),
            ("testBadRequest", testBadRequest),
            ("testBadRequestFollowingGoodRequest", testBadRequestFollowingGoodRequest),
        ]
    }
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }

    /// Tests the resolution of Kitura issue 1143: SSL socket listener becomes blocked and
    /// does not accept further connections if a 'bad' connection is made that then sends
    /// no data (where the server is waiting on SSL_accept to receive a handshake).
    ///
    /// The sequence of steps that cause a hang:
    ///
    /// - A non-SSL client connects to SSL listener port, then does nothing
    /// - On the server side, the listener thread expects an SSL client to be connecting.
    ///   It invokes the SSL delegate, goes into SSL_accept and then blocks, waiting for 
    ///   an SSL handshake (which will never arrive)
    /// - Another (well-behaved) SSL client attempts to connect. This hangs, because the
    ///   thread that normally loops around accepting incoming connections is still blocked
    ///   trying to SSL_accept the previous connection.
    ///
    /// The fix for this issue is to decouple the socket accept from the SSL handshake, and
    /// perform the latter on a separate thread. The expected behaviour is that a 'bad'
    /// (non-SSL) connection does not interfere with the server's ability to accept other
    /// connections.
    func testIssue1143() {
        do {
            let server: HTTPServer
            let serverPort: Int
            (server, serverPort) = try startEphemeralServer(ClientE2ETests.TestServerDelegate(), useSSL: true)
            defer {
                server.stop()
            }

            // Queue a server stop operation in 1 second, in case the test hangs (socket listener blocks)
            let recoveryOperation = DispatchWorkItem {
                server.stop()
                XCTFail("Test did not complete (hung), server has been stopped")
            }
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(1), execute: recoveryOperation)
            
            let badClient = try BadClient()
            let goodClient = try GoodClient()

            defer {
                badClient.disconnect()
                goodClient.disconnect()
            }
            
            /// Connect a 'bad' (non-SSL) client to the server
            try badClient.connect(serverPort)
            XCTAssertEqual(badClient.connectedPort, serverPort, "BadClient not connected to expected server port")
            XCTAssertFalse(badClient.socket.isSecure, "Expected BadClient socket to be insecure")
            
            /// Connect a 'good' (SSL enabled) client to the server
            try goodClient.connect(serverPort)
            XCTAssertEqual(goodClient.connectedPort, serverPort, "GoodClient not connected to expected server port")
            XCTAssertTrue(goodClient.socket.isSecure, "Expected GoodClient socket to be secure")

            /// Test succeeded (did not hang)
            recoveryOperation.cancel()
            
        } catch {
            XCTFail("Error: \(error)")
        }
    }
    
    /// A simple client based on BlueSocket, which connects to a port but sends no data
    struct BadClient {
        let socket: Socket
        
        var connectedPort: Int {
            return Int(self.socket.remotePort)
        }
            
        init() throws {
            socket = try Socket.create()
        }
        
        func connect(_ port: Int) throws {
            try socket.connect(to: "localhost", port: Int32(port))
        }
        
        func disconnect() {
            socket.close()
        }
        
    }

    /// A simple client based on BlueSSLService, which connects to a port and performs
    /// an SSL handshake
    struct GoodClient {
        let socket: Socket
        
        var connectedPort: Int {
            return Int(self.socket.remotePort)
        }
        
        init() throws {
            socket = try Socket.create()
            socket.delegate = try SSLService(usingConfiguration: clientSSLConfig)
        }
        
        func connect(_ port: Int) throws {
            try socket.connect(to: "localhost", port: Int32(port))
        }
        
        func disconnect() {
            socket.close()
        }
        
    }
    
    /// Tests that attempting to start a second HTTPServer on the same port fails.
    func testServersCollidingOnPort() {
        do {
            let server: HTTPServer
            let serverPort: Int
            (server, serverPort) = try startEphemeralServer(ClientE2ETests.TestServerDelegate(), useSSL: false)
            defer {
                server.stop()
            }
            
            do {
                let collidingServer: HTTPServer = try startServer(nil, port: serverPort, useSSL: false)
                defer {
                    collidingServer.stop()
                }
                XCTFail("Server unexpectedly succeeded in listening on a port already in use")
            } catch {
                XCTAssert(error is Socket.Error, "Expected a Socket.Error, received: \(error)")
            }
            
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    /// Tests that attempting to start a second HTTPServer on the same port with
    /// SO_REUSEPORT enabled is successful.
    func testServersSharingPort() {
        do {
            let server: HTTPServer = try startServer(nil, port: 0, useSSL: false, allowPortReuse: true)
            defer {
                server.stop()
            }
            
            guard let serverPort = server.port else {
                XCTFail("Server port was not initialized")
                return
            }
            XCTAssertTrue(serverPort != 0, "Ephemeral server port not set")
            
            do {
                let sharingServer: HTTPServer = try startServer(nil, port: serverPort, useSSL: false, allowPortReuse: true)
                sharingServer.stop()
            } catch {
                XCTFail("Second server could not share listener port, received: \(error)")
            }
            
        } catch {
            XCTFail("Error: \(error)")
        }
    }
    
    /// Tests that sending a bad request results in a `400/Bad Request` response
    /// from the server with `Connection: Close` header.
    func testBadRequest() {
        let requestBuffer = "GET / HTTP/1.1\r\nFOO\r\n\r\n"
        do {
            let server: HTTPServer
            let serverPort: Int
            (server, serverPort) = try startEphemeralServer(ClientE2ETests.TestServerDelegate(), useSSL: false)
            defer {
                server.stop()
            }
            
            // Send request to the server
            let clientSocket = try Socket.create()
            try clientSocket.connect(to: "localhost", port: Int32(serverPort))
            defer {
                clientSocket.close()
            }
            try clientSocket.write(from: requestBuffer)
            
            // Queue a recovery task to close our socket so that the test cannot wait forever
            // waiting for responses from the server
            let recoveryTask = DispatchWorkItem {
                XCTFail("Timed out waiting for responses from server")
                clientSocket.close()
            }
            let timeout = DispatchTime.now() + .seconds(1)
            DispatchQueue.global().asyncAfter(deadline: timeout, execute: recoveryTask)
            
            // Read responses from the server
            let buffer = NSMutableData(capacity: 2000)!
            var read = 0
            var bufferPosition = 0
            let response = ClientResponse()
            while true {
                XCTAssert(read == buffer.length, "Bytes read does not equal buffer length")
                let status = response.parse(buffer, from: bufferPosition)
                bufferPosition = buffer.length - status.bytesLeft
                if status.state == .messageComplete {
                    break
                }
                read += try clientSocket.read(into: buffer)
            }
            // Check that the response indicates failure
            validate400Response(response: response, responseNumber: 1)
            // We completed reading the responses, cancel the recovery task
            recoveryTask.cancel()
            XCTAssert(bufferPosition == buffer.length, "Unparsed bytes remaining after final response")
            
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    /// Tests that sending a good request followed by garbage on a Keep-Alive
    /// connection results in a `200/OK` response, followed by a `400/Bad Request`
    /// response with `Connection: Close` header.
    /// This is to verify the fix introduced in Kitura-net PR #229, where a malformed
    /// request sent during a Keep-Alive session could cause the server to crash.
    func testBadRequestFollowingGoodRequest() {
        let requestBuffer = "GET / HTTP/1.1\r\n\r\nFOO\r\n"
        let totalRequests = 2
        do {
            let server: HTTPServer
            let serverPort: Int
            (server, serverPort) = try startEphemeralServer(ClientE2ETests.TestServerDelegate(), useSSL: false)
            defer {
                server.stop()
            }
            
            // Send requests to the server
            let clientSocket = try Socket.create()
            try clientSocket.connect(to: "localhost", port: Int32(serverPort))
            defer {
                clientSocket.close()
            }
            try clientSocket.write(from: requestBuffer)
            
            // Queue a recovery task to close our socket so that the test cannot wait forever
            // waiting for responses from the server
            let recoveryTask = DispatchWorkItem {
                XCTFail("Timed out waiting for responses from server")
                clientSocket.close()
            }
            let timeout = DispatchTime.now() + .seconds(1)
            DispatchQueue.global().asyncAfter(deadline: timeout, execute: recoveryTask)
            
            // Read responses from the server
            let buffer = NSMutableData(capacity: 2000)!
            var read = 0
            var bufferPosition = 0
            var responsesToRead = totalRequests
            while responsesToRead > 0 {
                responsesToRead -= 1
                let response = ClientResponse()
                while true {
                    XCTAssert(read == buffer.length, "Bytes read does not equal buffer length")
                    let status = response.parse(buffer, from: bufferPosition)
                    bufferPosition = buffer.length - status.bytesLeft
                    if status.state == .messageComplete {
                        break
                    }
                    read += try clientSocket.read(into: buffer)
                }
                let responseNumber = totalRequests - responsesToRead
                switch responseNumber {
                case 1:
                    validate200Response(response: response, responseNumber: responseNumber)
                case 2:
                    validate400Response(response: response, responseNumber: responseNumber)
                default:
                    XCTFail("Unexpected responseNumber \(responseNumber)")
                }
                // Check that the response indicates success
                
            }
            // We completed reading the responses, cancel the recovery task
            recoveryTask.cancel()
            XCTAssert(bufferPosition == buffer.length, "Unparsed bytes remaining after final response")
            
        } catch {
            XCTFail("Error: \(error)")
        }
    }
    
    /// Checks that the provided ClientResponse represents an HTTP `200 OK`
    /// response from the server with an appropriate `Connection: Keep-Alive`
    /// header.
    private func validate200Response(response: ClientResponse, responseNumber: Int) {
        XCTAssert(response.httpStatusCode == .OK, "Response \(responseNumber) was not 200/OK, was \(response.httpStatusCode)")
        guard let connectionHeader = response.headers["Connection"] else {
            XCTFail("Response did not contain a 'Connection' header")
            return
        }
        guard connectionHeader.count == 1 else {
            XCTFail("Connection header did not have a single value: \(connectionHeader)")
            return
        }
        let connectionValue = connectionHeader[0]
        XCTAssert(connectionValue == "Keep-Alive", "Response 'Connection' header should be 'Keep-Alive', but was \(connectionValue)")
    }
    
    /// Checks that the provided ClientResponse represents an HTTP `400 Bad Request`
    /// response from the server with an appropriate `Connection: Close` header.
    private func validate400Response(response: ClientResponse, responseNumber: Int) {
        XCTAssert(response.httpStatusCode == .badRequest, "Response was not 400/Bad Request, was \(response.httpStatusCode)")
        guard let connectionHeader = response.headers["Connection"] else {
            XCTFail("Response did not contain a 'Connection' header")
            return
        }
        guard connectionHeader.count == 1 else {
            XCTFail("Connection header did not have a single value: \(connectionHeader)")
            return
        }
        let connectionValue = connectionHeader[0]
        XCTAssert(connectionValue == "Close", "Response 'Connection' header should be 'Close', but was \(connectionValue)")
    }

}
