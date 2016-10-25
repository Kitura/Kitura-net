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

class MiscellaneousTests: XCTestCase {
    
    static var allTests : [(String, (MiscellaneousTests) -> () throws -> Void)] {
        return [
            ("testError", testError),
            ("testEscape", testEscape),
            ("testHTTPIncomingMessage", testHTTPIncomingMessage)
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
    
    func testHTTPIncomingMessage() {
        let message = HTTPIncomingMessage(isRequest: true)
        
        XCTAssertEqual(message.parse(NSData()).error, HTTPParserErrorType.unexpectedEOF, "Parse should have errored with error=\(HTTPParserErrorType.unexpectedEOF)")
        
        message.release()
        XCTAssertEqual(message.parse(NSData()).error, HTTPParserErrorType.internalError, "Parse should have errored with error=\(HTTPParserErrorType.internalError)")
    }
}
