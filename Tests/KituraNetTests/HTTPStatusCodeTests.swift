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
  
  func testSuccessRange() {
    let rawOK = HTTPStatusCode(rawValue: 200)
    XCTAssertNotNil(rawOK)
    if let rawOK = rawOK {
        XCTAssertTrue(HTTPStatusCode.successRange.contains(rawOK))
    }
    XCTAssertTrue(HTTPStatusCode.successRange.contains(.OK))

    let rawContinue = HTTPStatusCode(rawValue: 100)
    XCTAssertNotNil(rawContinue)
    if let rawContinue = rawContinue {
        XCTAssertFalse(HTTPStatusCode.successRange.contains(rawContinue))
    }
    XCTAssertFalse(HTTPStatusCode.successRange.contains(.`continue`))

    let rawMultipleChoices = HTTPStatusCode(rawValue: 300)
    XCTAssertNotNil(rawMultipleChoices)
    if let rawMultipleChoices = rawMultipleChoices {
        XCTAssertFalse(HTTPStatusCode.successRange.contains(rawMultipleChoices))
    }
    XCTAssertFalse(HTTPStatusCode.successRange.contains(.multipleChoices))
  }

  func testServerErrorRange() {
    let rawInternalError = HTTPStatusCode(rawValue: 500)
    XCTAssertNotNil(rawInternalError)
    if let rawInternalError = rawInternalError {
        XCTAssertTrue(HTTPStatusCode.serverErrorRange.contains(rawInternalError))
    }
    XCTAssertTrue(HTTPStatusCode.serverErrorRange.contains(.internalServerError))

    let rawNetAuthReqd = HTTPStatusCode(rawValue: 511)
    XCTAssertNotNil(rawNetAuthReqd)
    if let rawNetAuthReqd = rawNetAuthReqd {
        XCTAssertTrue(HTTPStatusCode.serverErrorRange.contains(rawNetAuthReqd))
    }
    XCTAssertTrue(HTTPStatusCode.serverErrorRange.contains(.networkAuthenticationRequired))

    let rawBadRequest = HTTPStatusCode(rawValue: 400)
    XCTAssertNotNil(rawBadRequest)
    if let rawBadRequest = rawBadRequest {
        XCTAssertFalse(HTTPStatusCode.serverErrorRange.contains(rawBadRequest))
    }
    XCTAssertFalse(HTTPStatusCode.serverErrorRange.contains(.badRequest))
  }

}

extension HTTPStatusCodeTests {
  static var allTests : [(String, (HTTPStatusCodeTests) -> () throws -> Void)] {
    return [
             ("testSuccessRange", testSuccessRange),
             ("testServerErrorRange", testServerErrorRange),
    ]
  }
}
