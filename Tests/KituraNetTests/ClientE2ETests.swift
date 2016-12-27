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

class ClientE2ETests: XCTestCase {

    static var allTests : [(String, (ClientE2ETests) -> () throws -> Void)] {
        return [
            ("testErrorRequests", testErrorRequests),
            ("testHeadRequests", testHeadRequests),
            ("testPostRequests", testPutRequests),
            ("testPutRequests", testPostRequests),
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
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
                do {
                    var data = Data()
                    let count = try response!.readAllData(into: &data)
                    XCTAssertEqual(count, 0, "Result should have been zero bytes, was \(count) bytes")
                }
                catch {
                    XCTFail("Failed reading the body of the response")
                }
                expectation.fulfill()
            })
        }
    }
    
    func testSimpleHTTPClient() {
        _ = HTTP.get("http://www.ibm.com") {response in
            XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
            XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "HTTP Status code was \(response!.statusCode)")
            let contentType = response!.headers["Content-Type"]
            XCTAssertNotNil(contentType, "No ContentType header in response")
            XCTAssertEqual(contentType!, ["text/html"], "Content-Type header wasn't `text/html`")
        }
    }
    
    func testPostRequests() {
        performServerTest(delegate, asyncTasks: { expectation in
            self.performRequest("post", path: "/posttest", callback: {response in
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
                do {
                    var data = Data()
                    let count = try response!.readAllData(into: &data)
                    XCTAssertEqual(count, 12, "Result should have been 12 bytes, was \(count) bytes")
                    let postValue = String(data: data as Data, encoding: .utf8)
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
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
                do {
                    var data = Data()
                    let count = try response!.readAllData(into: &data)
                    XCTAssertEqual(count, 13, "Result should have been 13 bytes, was \(count) bytes")
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
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
                do {
                    var data = Data()
                    let count = try response!.readAllData(into: &data)
                    XCTAssertEqual(count, 12, "Result should have been 12 bytes, was \(count) bytes")
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
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
                do {
                    var data = Data()
                    let count = try response!.readAllData(into: &data)
                    XCTAssertEqual(count, 13, "Result should have been 13 bytes, was \(count) bytes")
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
    
    func testErrorRequests() {
        performServerTest(delegate, asyncTasks: { expectation in
            self.performRequest("plover", path: "/xzzy", callback: {response in
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.badRequest, "Status code wasn't .badrequest was \(response!.statusCode)")
                expectation.fulfill()
            })
        })
    }
    
    func testUrlURL() {
        performServerTest(TestURLDelegate()) { expectation in
            self.performRequest("post", path: ClientE2ETests.urlPath, callback: {response in
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
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
                response.headers["Content-Type"] = ["text/plain"]
                if request.method.lowercased() != "head" {
                    response.headers["Content-Length"] = ["\(result.characters.count)"]
                }
                
                try response.end(text: result)
            }
            catch {
                print("Error writing response")
            }
        }
    }
    
    class TestURLDelegate: ServerDelegate {
        
        func handle(request: ServerRequest, response: ServerResponse) {
            XCTAssertEqual(request.urlURL.path, urlPath, "Path in request.urlURL wasn't \(urlPath), it was \(request.urlURL.port)")
            XCTAssertEqual(request.urlURL.port, 8090, "The port in request.urlURL wasn't 8090, it was \(request.urlURL.port)")
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
