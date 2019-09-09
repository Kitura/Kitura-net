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

class ClientRequestTests: KituraNetTest {
    let testCallback: ClientRequest.Callback = {_ in }

    private func httpBasicAuthHeader(username: String, password: String) -> String {
        let authHeader = "\(username):\(password)"
        let data = Data(authHeader.utf8)
        return "Basic \(data.base64EncodedString())"
    }
  
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

  func testClientRequestSet() {

    let testRequest = ClientRequest(url: "https://66o.tech:8080", callback: testCallback)

    // ensure setting non-URL options does not effect the URL
    testRequest.set(.method("delete"))
    testRequest.set(.headers(["X-Custom": "Swift"]))
    testRequest.set(.maxRedirects(3))
    testRequest.set(.disableSSLVerification)

    XCTAssertEqual(testRequest.url, "https://66o.tech:8080")
  }

  func testClientRequestParse() {
      
    let options = ClientRequest.parse("https://66o.tech:8080/path?key=value")
    let testRequest = ClientRequest(options: options, callback: testCallback)
    XCTAssertEqual(testRequest.url, "https://66o.tech:8080/path?key=value")
  }

  func testClientRequestBasicAuthentcation() {
      
    // ensure an empty password works
    let options: [ClientRequest.Options] = [ .username("myusername"),
                                             .hostname("66o.tech")
    ]
    var testRequest = ClientRequest(options: options, callback: testCallback)
    XCTAssertNil(testRequest.headers["Authorization"])
    XCTAssertEqual(testRequest.userName,"myusername")
    XCTAssertEqual(testRequest.url, "http://66o.tech")

    // ensure an empty username works
    let options2: [ClientRequest.Options] = [ .password("mypassword"),
                                              .hostname("66o.tech")
    ]
    testRequest = ClientRequest(options: options2, callback: testCallback)
    XCTAssertNil(testRequest.headers["Authorization"])
    XCTAssertEqual(testRequest.password, "mypassword")
    XCTAssertEqual(testRequest.url, "http://66o.tech")

    // ensure username:password works
    let options3: [ClientRequest.Options] = [ .username("myusername"),
                                              .password("mypassword"),
                                              .hostname("66o.tech")
    ]
    testRequest = ClientRequest(options: options3, callback: testCallback)
    let authHeaderValue = testRequest.headers["Authorization"] ?? ""
    XCTAssertEqual(authHeaderValue, httpBasicAuthHeader(username: "myusername", password: "mypassword"))
    XCTAssertEqual(testRequest.url, "http://66o.tech")
}

}

extension ClientRequestTests {
  static var allTests : [(String, (ClientRequestTests) -> () throws -> Void)] {
    return [
             ("testClientRequestWhenInitializedWithValidURL", testClientRequestWhenInitializedWithValidURL),
             ("testClientRequestWhenInitializedWithSimpleSchema",
              testClientRequestWhenInitializedWithSimpleSchema),
             ("testClientRequestDefaultSchemaIsHTTP", testClientRequestDefaultSchemaIsHTTP),
             ("testClientRequestDefaultMethodIsGET", testClientRequestDefaultMethodIsGET),
             ("testClientRequestAppendsPathCorrectly", testClientRequestAppendsPathCorrectly),
             ("testClientRequestAppendsMisformattedPathCorrectly", testClientRequestAppendsMisformattedPathCorrectly),
             ("testClientRequestAppendsPort", testClientRequestAppendsPort),
             ("testClientRequestSet", testClientRequestSet),
             ("testClientRequestParse", testClientRequestParse),
             ("testClientRequestBasicAuthentcation", testClientRequestBasicAuthentcation)
    ]
  }
}
