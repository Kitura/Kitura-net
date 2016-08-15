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

class ClientRequestTests: XCTestCase {
  let testCallback: ClientRequest.Callback = {_ in }

  // 1 test URL that is build when initializing with ClientRequestOptions
  func testClientRequestWhenInitializedWithValidURL() {
    let options: [ClientRequest.Options] = [ .method("GET"),
                                            .schema("https://"),
                                            .hostname("66o.tech")
                                            ]
    let testRequest = ClientRequest(options: options, callback: testCallback)

    XCTAssertEqual(testRequest.url, "https://66o.tech")
  }

  func testClientRequestWhenInitializedWithSimpleSchema() {
    let options: [ClientRequest.Options] = [ .method("GET"),
                                            .schema("https"),
                                            .hostname("66o.tech")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)

    XCTAssertEqual(testRequest.url, "https://66o.tech")
  }

  func testClientRequestDefaultSchemaIsHTTP() {
    let options: [ClientRequest.Options] = [ .method("GET"),
                                            .hostname("66o.tech")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)

    XCTAssertEqual(testRequest.url, "http://66o.tech")
  }

  func testClientRequestDefaultMethodIsGET() {
    let options: [ClientRequest.Options] = [ .schema("https"),
                                            .hostname("66o.tech")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)

    XCTAssertEqual(testRequest.method, "get")
  }

  func testClientRequestAppendsPathCorrectly() {
    let options: [ClientRequest.Options] = [ .schema("https"),
                                            .hostname("66o.tech"),
                                            .path("path/to/resource")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)

    XCTAssertEqual(testRequest.url, "https://66o.tech/path/to/resource")
  }

  func testClientRequestAppendsMisformattedPathCorrectly() {
    let options: [ClientRequest.Options] = [ .schema("https"),
                                            .hostname("66o.tech"),
                                            .path("/path/to/resource")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)

    XCTAssertEqual(testRequest.url, "https://66o.tech/path/to/resource")
  }

  func testClientRequestAppendsPort() {
    let options: [ClientRequest.Options] = [ .schema("https"),
                                            .hostname("66o.tech"),
                                            .port(8080)
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)

    XCTAssertEqual(testRequest.url, "https://66o.tech:8080")
  }

}

extension ClientRequestTests {
  static var allTests: [(String, (ClientRequestTests) -> () throws -> Void)] {
    return [
             ("testClientRequestWhenInitializedWithValidURL", testClientRequestWhenInitializedWithValidURL),
             ("testClientRequestWhenInitializedWithSimpleSchema",
              testClientRequestWhenInitializedWithSimpleSchema),
             ("testClientRequestDefaultSchemaIsHTTP", testClientRequestDefaultSchemaIsHTTP),
             ("testClientRequestDefaultMethodIsGET", testClientRequestDefaultMethodIsGET),
             ("testClientRequestAppendsPathCorrectly", testClientRequestAppendsPathCorrectly),
             ("testClientRequestAppendsMisformattedPathCorrectly", testClientRequestAppendsMisformattedPathCorrectly),
             ("testClientRequestAppendsPort", testClientRequestAppendsPort)
    ]
  }
}
