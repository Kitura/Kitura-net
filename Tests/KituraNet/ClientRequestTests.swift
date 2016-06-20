//
//  ClientRequestTests.swift
//  Kitura-net
//
//  Created by Michał Kalinowski on 26/05/16.
//
//

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

  func testClientRequestAppendsPostFields() {
    let options: [ClientRequest.Options] = [ .schema("https"),
                                            .hostname("66o.tech"),
                                            .postFields("post_body"),
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.postFields, "post_body")
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
             ("testClientRequestAppendsPostFields", testClientRequestAppendsPostFields),
    ]
  }
}
