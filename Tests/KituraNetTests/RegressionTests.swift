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
                defer {
                    sharingServer.stop()
                }
            } catch {
                XCTFail("Second server could not share listener port, received: \(error)")
            }
            
        } catch {
            XCTFail("Error: \(error)")
        }
    }

}
