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

class MiscellaneousTests: KituraNetTest {
    
    static var allTests : [(String, (MiscellaneousTests) -> () throws -> Void)] {
        return [
            ("testError", testError),
            ("testEscape", testEscape),
            ("testHeadersContainers", testHeadersContainers)
        ]
    }
    
    func testError() {
        let errorCode: Int32 = 5
        let reason = "Testing 1 2 3"
        let error = Error.incomingSocketManagerFailure(errorCode: errorCode, reason: reason)
        XCTAssertEqual(error.description, "Failed to handle incoming socket. Error code=\(errorCode). Reason=\(reason)", "Description was incorrect. It was \(error.description)")
    }
    
    func testEscape() {
        let testString = "#%?"
        let desiredResult = "%23%25%3F"
        
        XCTAssertEqual(HTTP.escape(url: testString), desiredResult, "Escape of \"\(testString)\" wasn't \"\(desiredResult)\", it was \"\(HTTP.escape(url: testString))\"")
    }
    
    func testHeadersContainers() {
        let headers = HeadersContainer()
        headers.append("Set-Cookie", value: "plover=xyzzy")
        headers.append("Set-Cookie", value: "kitura=great")
        headers.append("Content-Type", value: "text/plain")
        
        var foundSetCookie = false
        var foundContentType = false
        
        for (key, value) in headers {
            switch(key.lowercased()) {
            case "content-type":
                XCTAssertEqual(value.count, 1, "Content-Type didn't have only one value. It had \(value.count) values")
                XCTAssertEqual(value[0], "text/plain", "Expecting a value of text/plain. Found \(value[0])")
                foundContentType = true
                
            case "set-cookie":
                XCTAssertEqual(value.count, 2, "Set-Cookie didn't have two values. It had \(value.count) values")
                foundSetCookie = true
                
            default:
                XCTFail("Found a header other than Content-Type or Set-Cookie (\(key))")
            }
        }
        XCTAssert(foundContentType, "Didn't find the Content-Type header")
        XCTAssert(foundSetCookie, "Didn't find the Set-Cookie header")
    }
}
