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
            ("testSimpleHTTPClient", testSimpleHTTPClient),
            ("testPostRequests", testPostRequests)
        ]
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    let delegate = ServerDelegate()
    
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
                    let data = NSMutableData()
                    let count = try response!.readAllData(into: data)
                    XCTAssertEqual(count, 12, "Result should have been 12 bytes, was \(count) bytes")
                    if  let postValue = String(data: data, encoding: NSUTF8StringEncoding) {
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
                    let data = NSMutableData()
                    let count = try response!.readAllData(into: data)
                    XCTAssertEqual(count, 13, "Result should have been 13 bytes, was \(count) bytes")
                    if  let postValue = String(data: data, encoding: NSUTF8StringEncoding) {
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
    
    class ServerDelegate : HTTPServerDelegate {
    
        func handle(request: ServerRequest, response: ServerResponse) {
            let body = NSMutableData()
            do {
                let length = try request.readAllData(into: body)
                let result = "Read \(length) bytes"
                response.headers["Content-Type"] = ["text/plain"]
                response.headers["Content-Length"] = ["\(result.characters.count)"]
            
                try response.end(text: result)
            }
            catch {
                print("Error reading body or writing response")
            }
        }
    }
}
