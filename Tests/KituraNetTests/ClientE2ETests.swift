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

class ClientE2ETests: KituraNetTest {

    static var allTests : [(String, (ClientE2ETests) -> () throws -> Void)] {
        return [
            ("testEphemeralListeningPort", testEphemeralListeningPort),
            ("testErrorRequests", testErrorRequests),
            ("testHeadRequests", testHeadRequests),
            ("testKeepAlive", testKeepAlive),
            ("testPostRequests", testPostRequests),
            ("testPutRequests", testPutRequests),
            ("testPatchRequests", testPatchRequests),
            ("testPipelining", testPipelining),
            ("testPipeliningSpanningPackets", testPipeliningSpanningPackets),
            ("testSimpleHTTPClient", testSimpleHTTPClient),
            ("testUrlURL", testUrlURL)
        ]
    }

    override func setUp() {
        doSetUp()
    }

    override func tearDown() {
        doTearDown()
    }
    
    static let urlPath = "/urltest"
    
    let delegate = TestServerDelegate()
    
    func testHeadRequests() {
        performServerTest(delegate) { expectation in
            self.performRequest("head", path: "/headtest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                do {
                    var data = Data()
                    let count = try response?.readAllData(into: &data)
                    XCTAssertEqual(count, 0, "Result should have been zero bytes, was \(String(describing: count)) bytes")
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                XCTAssertEqual(response?.httpVersionMajor, 1, "HTTP Major code from KituraNet should be 1, was \(String(describing: response?.httpVersionMajor))")
                XCTAssertEqual(response?.httpVersionMinor, 1, "HTTP Minor code from KituraNet should be 1, was \(String(describing: response?.httpVersionMinor))")
                expectation.fulfill()
            })
        }
    }
    
    func testKeepAlive() {
        performServerTest(delegate, asyncTasks: { expectation in
            self.performRequest("get", path: "/posttest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .OK was \(String(describing: response?.statusCode))")
                if let connectionHeader = response?.headers["Connection"] {
                    XCTAssertEqual(connectionHeader.count, 1, "The Connection header didn't have only one value. Value=\(connectionHeader)")
                    XCTAssertEqual(connectionHeader[0], "Close", "The Connection header didn't have a value of 'Close' (was \(connectionHeader[0]))")
                }
                expectation.fulfill()
            })
        },
        { expectation in
            self.performRequest("get", path: "/posttest", close: false, callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .OK was \(String(describing: response?.statusCode))")
                if let connectionHeader = response?.headers["Connection"] {
                    XCTAssertEqual(connectionHeader.count, 1, "The Connection header didn't have only one value. Value=\(connectionHeader)")
                    XCTAssertEqual(connectionHeader[0], "Keep-Alive", "The Connection header didn't have a value of 'Keep-Alive' (was \(connectionHeader[0]))")
                }
                expectation.fulfill()
            })
        })
    }
    
    /// Tests that the server responds appropriately to pipelined requests.
    /// Three POST requests are sent to a test server in a single socket write. The
    /// server is expected to process them sequentially, sending three separate
    /// responses, each indicating that a body of 6 bytes was received.
    func testPipelining() {
        let postRequest = "POST / HTTP/1.1\r\nHost: localhost:8080\r\nContent-Length: 6\r\n\r\nabcdef"
        let expectedResponse = "Read 6 bytes"
        let totalRequests = 3
        let pipelinedRequests = String(repeating: postRequest, count: totalRequests)
        doPipelineTest(expecting: expectedResponse, totalRequests: totalRequests) {
            socket in
            try socket.write(from: pipelinedRequests)
        }
    }
        
    /// Tests that the server responds appropriately to pipelined requests.
    /// Three POST requests are sent to a test server in a pipelined fashion, but
    /// spanning several packets. It is necessary to sleep between writes to allow
    /// the server time to receive and process the data.
    func testPipeliningSpanningPackets() {
        let firstBuffer = "POST / HTTP/1.1\r\nHost: localhost:8080\r\nContent-Length: 6\r\n\r\nabcdefPOST / HTTP/1.1\r\nHost: localhost:80"
        let secondBuffer = "80\r\nContent-Length: 6\r\n\r\nabcdefPO"
        let thirdBuffer = "ST / HTTP/1.1\r\nHost: localhost:8080\r\nContent-Length: 6\r\n\r\nabcdef"
        let expectedResponse = "Read 6 bytes"
        let totalRequests = 2
        doPipelineTest(expecting: expectedResponse, totalRequests: totalRequests) {
            socket in
            // Disable Nagle's algorithm on this socket to flush first write
            var on: Int32 = 1
            setsockopt(socket.socketfd, Int32(IPPROTO_TCP), TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
            try socket.write(from: firstBuffer)
            usleep(1000)
            try socket.write(from: secondBuffer)
            usleep(1000)
            try socket.write(from: thirdBuffer)
        }
    }
    
    private func doPipelineTest(expecting expectedResponse: String, totalRequests: Int, writer: (Socket) throws -> Void) {
        do {
            let server: HTTPServer = try startServer(TestServerDelegate(), port: 0, useSSL: false)
            defer {
                server.stop()
            }
            
            guard let serverPort = server.port else {
                XCTFail("Server port was not initialized")
                return
            }
            XCTAssertTrue(serverPort != 0, "Ephemeral server port not set")
            
            // Send pipelined requests to the server
            let clientSocket = try Socket.create()
            try clientSocket.connect(to: "localhost", port: Int32(serverPort))
            defer {
                clientSocket.close()
            }
            try writer(clientSocket)
            //try clientSocket.write(from: pipelinedRequests)
            
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
                // Check that the response indicates success
                XCTAssert(response.httpStatusCode == .OK, "Response \(responseNumber) was not 200/OK, was \(response.httpStatusCode)")
                guard let responseBody = try response.readString() else {
                    XCTFail("Unable to read body of response \(responseNumber)")
                    break
                }
                // Check that the response body contains the expected content
                if responseBody != expectedResponse {
                    XCTFail("Expected: '\(expectedResponse)', but response \(responseNumber) was: '\(responseBody)'")
                }
                print("ok \(responseNumber)")
            }
            // We completed reading the responses, cancel the recovery task
            recoveryTask.cancel()
            XCTAssert(bufferPosition == buffer.length, "Unparsed bytes remaining after final response")
            
        } catch {
            XCTFail("Error: \(error)")
        }
    }
    
    func testEphemeralListeningPort() {
        do {
            let server = try HTTPServer.listen(on: 0, delegate: delegate)
            _ = HTTP.get("http://localhost:\(server.port!)") { response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "HTTP Status code was \(String(describing: response?.statusCode))")
            }
            server.stop()
        } catch let error {
            XCTFail("Error: \(error)")
        }
    }

    func testSimpleHTTPClient() {
        _ = HTTP.get("http://www.ibm.com") {response in
            XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
            XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "HTTP Status code was \(String(describing: response?.statusCode))")
            let contentType = response?.headers["Content-Type"]
            XCTAssertNotNil(contentType, "No ContentType header in response")
            if let contentType = contentType {
                XCTAssertEqual(contentType, ["text/html"], "Content-Type header wasn't `text/html`")
            }
        }
    }
    
    func testPostRequests() {
        performServerTest(delegate, asyncTasks: { expectation in
            self.performRequest("post", path: "/posttest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                do {
                    let postValue = try response?.readString()
                    XCTAssertNotNil(postValue, "The body of the response was empty")
                    XCTAssertEqual(postValue?.characters.count, 12, "Result should have been 12 bytes, was \(String(describing: postValue?.characters.count)) bytes")
                    if  let postValue = postValue {
                        XCTAssertEqual(postValue, "Read 0 bytes")
                    }
                    else {
                        XCTFail("postValue's value wasn't an UTF8 string")
                    }
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                expectation.fulfill()
            })
        },
        { expectation in
            self.performRequest("post", path: "/posttest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                do {
                    var data = Data()
                    let count = try response?.readAllData(into: &data)
                    XCTAssertEqual(count, 13, "Result should have been 13 bytes, was \(String(describing: count)) bytes")
                    let postValue = String(data: data as Data, encoding: .utf8)
                    if  let postValue = postValue {
                        XCTAssertEqual(postValue, "Read 16 bytes")
                    }
                    else {
                        XCTFail("postValue's value wasn't an UTF8 string")
                    }
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                expectation.fulfill()
            }) {request in
                request.set(.disableSSLVerification)
                request.write(from: "A few characters")
            }
        })
    }

    func testPutRequests() {
        performServerTest(delegate, asyncTasks: { expectation in
            self.performRequest("put", path: "/puttest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                do {
                    var data = Data()
                    let count = try response?.readAllData(into: &data)
                    XCTAssertEqual(count, 12, "Result should have been 12 bytes, was \(String(describing: count)) bytes")
                    let putValue = String(data: data as Data, encoding: .utf8)
                    if  let putValue = putValue {
                        XCTAssertEqual(putValue, "Read 0 bytes")
                    }
                    else {
                        XCTFail("putValue's value wasn't an UTF8 string")
                    }
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                expectation.fulfill()
            })
        },
        { expectation in
            self.performRequest("put", path: "/puttest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                do {
                    var data = Data()
                    let count = try response?.readAllData(into: &data)
                    XCTAssertEqual(count, 13, "Result should have been 13 bytes, was \(String(describing: count)) bytes")
                    let postValue = String(data: data as Data, encoding: .utf8)
                    if  let postValue = postValue {
                        XCTAssertEqual(postValue, "Read 16 bytes")
                    }
                    else {
                        XCTFail("postValue's value wasn't an UTF8 string")
                    }
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                expectation.fulfill()
            }) {request in
                request.write(from: "A few characters")
            }
        })
    }    

    func testPatchRequests() {
        performServerTest(delegate, asyncTasks: { expectation in
            self.performRequest("patch", path: "/patchtest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                do {
                    var data = Data()
                    let count = try response?.readAllData(into: &data)
                    XCTAssertEqual(count, 12, "Result should have been 12 bytes, was \(String(describing: count)) bytes")
                    let patchValue = String(data: data as Data, encoding: .utf8)
                    if  let patchValue = patchValue {
                        XCTAssertEqual(patchValue, "Read 0 bytes")
                    }
                    else {
                        XCTFail("patchValue's value wasn't an UTF8 string")
                    }
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                expectation.fulfill()
            })
        },
        { expectation in
            self.performRequest("patch", path: "/patchtest", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                do {
                    var data = Data()
                    let count = try response?.readAllData(into: &data)
                    XCTAssertEqual(count, 13, "Result should have been 13 bytes, was \(String(describing: count)) bytes")
                    let patchValue = String(data: data as Data, encoding: .utf8)
                    if  let patchValue = patchValue {
                        XCTAssertEqual(patchValue, "Read 16 bytes")
                    }
                    else {
                        XCTFail("patchValue's value wasn't an UTF8 string")
                    }
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                expectation.fulfill()
            }) {request in
                request.write(from: "A few characters")
            }
        })
    }
    
    func testErrorRequests() {
        performServerTest(delegate, asyncTasks: { expectation in
            self.performRequest("plover", path: "/xzzy", callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.badRequest, "Status code wasn't .badrequest was \(String(describing: response?.statusCode))")
                expectation.fulfill()
            })
        })
    }
    
    func testUrlURL() {
        performServerTest(TestURLDelegate()) { expectation in
            self.performRequest("post", path: ClientE2ETests.urlPath, callback: {response in
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(String(describing: response?.statusCode))")
                expectation.fulfill()
            })
        }
    }
    
    class TestServerDelegate: ServerDelegate {
    
        func handle(request: ServerRequest, response: ServerResponse) {
            XCTAssertEqual(request.remoteAddress, "127.0.0.1", "Remote address wasn't 127.0.0.1, it was \(request.remoteAddress)")
            
            let result: String
            switch request.method.lowercased() {
            case "head":
                result = "This a really simple head request result"
            
            case "put":
                do {
                    var body = try request.readString()
                    result = "Read \(body?.characters.count ?? 0) bytes"
                }
                catch {
                    print("Error reading body")
                    result = "Read -1 bytes"
                }
                
            default:
                var body = Data()
                do {
                    let length = try request.readAllData(into: &body)
                    result = "Read \(length) bytes"
                }
                catch {
                    print("Error reading body")
                    result = "Read -1 bytes"
                }
            }
            
            do {
                response.statusCode = .OK
                XCTAssertEqual(response.statusCode, .OK, "Set response status code wasn't .OK, it was \(String(describing: response.statusCode))")
                response.headers["Content-Type"] = ["text/plain"]
                response.headers["Content-Length"] = ["\(result.characters.count)"]
                
                try response.end(text: result)
            }
            catch {
                print("Error writing response")
            }
        }
    }
    
    class TestURLDelegate: ServerDelegate {
        
        func handle(request: ServerRequest, response: ServerResponse) {
            XCTAssertEqual(request.httpVersionMajor, 1, "HTTP Major code from KituraNet should be 1, was \(String(describing: request.httpVersionMajor))")
            XCTAssertEqual(request.httpVersionMinor, 1, "HTTP Minor code from KituraNet should be 1, was \(String(describing: request.httpVersionMinor))")
            XCTAssertEqual(request.urlURL.path, urlPath, "Path in request.urlURL wasn't \(urlPath), it was \(request.urlURL.path)")
            XCTAssertEqual(request.urlURL.port, KituraNetTest.portDefault)
            XCTAssertEqual(request.url, urlPath.data(using: .utf8))
            do {
                response.statusCode = .OK
                let result = "OK"
                response.headers["Content-Type"] = ["text/plain"]
                let resultData = result.data(using: .utf8)!
                response.headers["Content-Length"] = ["\(resultData.count)"]
                
                try response.write(from: resultData)
                try response.end()
            }
            catch {
                print("Error reading body or writing response")
            }
        }
    }
}
