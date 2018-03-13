/**
 * Copyright IBM Corporation 2018
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

class HTTPStatusCodeTests: KituraNetTest {
 
  // Test that a valid status code can be created, and is correctly mapped to its status class. 
  func testStatusCodeCreation() {
    let myOK = HTTPStatusCode(rawValue: 200)
    XCTAssertNotNil(myOK)
    if let myOK = myOK {
        XCTAssertTrue(myOK.class == .successful)
    }
  }

  // Test that an undefined status code cannot be created
  func testInvalidStatusCode() {
    let invalidStatus = HTTPStatusCode(rawValue: 418)
    XCTAssertNil(invalidStatus)
  }

  // Test that a status code in each category is correctly mapped to its status class.
  func testClassOfStatusCode() {
    XCTAssertTrue(HTTPStatusCode.OK.class == .successful)
    XCTAssertTrue(HTTPStatusCode.`continue`.class == .informational)
    XCTAssertTrue(HTTPStatusCode.multipleChoices.class == .redirection)
    XCTAssertTrue(HTTPStatusCode.badRequest.class == .clientError)
    XCTAssertTrue(HTTPStatusCode.internalServerError.class == .serverError)
  }

}

extension HTTPStatusCodeTests {
  static var allTests : [(String, (HTTPStatusCodeTests) -> () throws -> Void)] {
    return [
             ("testStatusCodeCreation", testStatusCodeCreation),
             ("testInvalidStatusCode", testInvalidStatusCode),
             ("testClassOfStatusCode", testClassOfStatusCode),
    ]
  }
}
