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
  let testCallback: ClientRequestCallback = {_ in }
  
  // 1 test URL that is build when initializing with ClientRequestOptions
  func testClientRequestWhenInitializedWithValidURL() {
    let options: [ClientRequestOptions] = [ .method("GET"),
                                            .schema("https://"),
                                            .hostname("66o.tech")
                                            ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.url, "https://66o.tech")
  }
  
  func testClientRequestWhenInitializedWithSimpleSchema() {
    let options: [ClientRequestOptions] = [ .method("GET"),
                                            .schema("https"),
                                            .hostname("66o.tech")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.url, "https://66o.tech")
  }
  
  func testClientRequestDefaultSchemaIsHTTP() {
    let options: [ClientRequestOptions] = [ .method("GET"),
                                            .hostname("66o.tech")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.url, "http://66o.tech")
  }
  
  func testClientRequestDefaultMethodIsGET() {
    let options: [ClientRequestOptions] = [ .schema("https"),
                                            .hostname("66o.tech")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.method, "get")
  }
  
  func testClientRequestAppendsPathCorrectly() {
    let options: [ClientRequestOptions] = [ .schema("https"),
                                            .hostname("66o.tech"),
                                            .path("path/to/resource")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.url, "https://66o.tech/path/to/resource")
  }
  
  func testClientRequestAppendsMisformattedPathCorrectly() {
    let options: [ClientRequestOptions] = [ .schema("https"),
                                            .hostname("66o.tech"),
                                            .path("/path/to/resource")
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.url, "https://66o.tech/path/to/resource")
  }
  
  func testClientRequestAppendsPort() {
    let options: [ClientRequestOptions] = [ .schema("https"),
                                            .hostname("66o.tech"),
                                            .port(8080)
    ]
    let testRequest = ClientRequest(options: options, callback: testCallback)
    
    XCTAssertEqual(testRequest.url, "https://66o.tech:8080")
  }
  
}
