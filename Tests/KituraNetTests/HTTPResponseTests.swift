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

class HTTPResponseTests: KituraNetTest {
    static var allTests : [(String, (HTTPResponseTests) -> () throws -> Void)] {
        return [
            ("testContentTypeHeaders", testContentTypeHeaders)
        ]
    }
    
    func testContentTypeHeaders() {
        let headers = HeadersContainer()
        
        headers.append("Content-Type", value: "text/html")
        var values = headers["Content-Type"]
        XCTAssertNotNil(values, "Couldn't retrieve just set Content-Type header")
        XCTAssertEqual(values?.count, 1, "Content-Type header should only have one value")
        XCTAssertEqual(values?[0], "text/html")
        
        headers.append("Content-Type", value: "text/plain; charset=utf-8")
        XCTAssertEqual(headers["Content-Type"]?[0], "text/html")
        
        headers["Content-Type"] = nil
        XCTAssertNil(headers["Content-Type"])
        
        headers.append("Content-Type", value: "text/plain, image/png")
        XCTAssertEqual(headers["Content-Type"]?[0], "text/plain, image/png")
        
        headers.append("Content-Type", value: "text/html, image/jpeg")
        XCTAssertEqual(headers["Content-Type"]?[0], "text/plain, image/png")
        
        headers.append("Content-Type", value: "charset=UTF-8")
        XCTAssertEqual(headers["Content-Type"]?[0], "text/plain, image/png")
        
        headers["Content-Type"] = nil
        
        headers.append("Content-Type", value: "text/html")
        XCTAssertEqual(headers["Content-Type"]?[0], "text/html")
        
        headers.append("Content-Type", value: "image/png, text/plain")
        XCTAssertEqual(headers["Content-Type"]?[0], "text/html")
    }
}
