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

class LargePayloadTests: XCTestCase {
    
    static var allTests : [(String, (LargePayloadTests) -> () throws -> Void)] {
        return [
            ("testLargePosts", testLargePosts)
        ]
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    let delegate = TestServerDelegate()
    
    func testLargePosts() {
        performServerTest(delegate, asyncTasks: { expectation in
            let payload = "[" + contentTypesString + "," + contentTypesString + contentTypesString + "," + contentTypesString + "]"
            self.performRequest("post", path: "/largepost", callback: {response in
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "Status code wasn't .Ok was \(response!.statusCode)")
                do {
                    let expectedResult = "Read \(payload.characters.count) bytes"
                    let data = NSMutableData()
                    let count = try response!.readAllData(into: data)
                    XCTAssertEqual(count, expectedResult.characters.count, "Result should have been \(expectedResult.characters.count) bytes, was \(count) bytes")
                    #if os(Linux)
                        let postValue = String(data: data, encoding: NSUTF8StringEncoding)
                    #else
                        let postValue = String(data: data as Data, encoding: String.Encoding.utf8)
                    #endif
                    if  let postValue = postValue {
                        XCTAssertEqual(postValue, expectedResult)
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
                request.write(from: payload)
            }
        })
    }
    
    class TestServerDelegate : ServerDelegate {
        
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
