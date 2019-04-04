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

import XCTest
@testable import KituraNet
import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

//
// Test that the FastCGI Record Creator and Parses classes work as expected.
// This is technically not a pure test since we're not using a reference
// implementation to generate the test packets but it does show that the parser and creator,
// which don't share code other than constants and exceptions, can interoperate.
//
// It would be embarrasingly broken if they did not...
//
class FastCGIProtocolTests: KituraNetTest {

    // All tests
    //
    static var allTests : [(String, (FastCGIProtocolTests) -> () throws -> Void)] {
        return [
            ("testNoRequestId", testNoRequestId),
            ("testBadRecordType", testBadRecordType),
            ("testRequestBeginKeepalive", testRequestBeginKeepalive),
            ("testRequestBeginNoKeepalive", testRequestBeginNoKeepalive),
            ("testParameters", testParameters),
            ("testDataOutput", testDataOutput),
            ("testDataInput", testDataOutput),
            ("testOversizeDataOutput", testOversizeDataOutput),
            ("testOversizeDataInput", testOversizeDataInput),
            ("testEndRequestSuccess", testEndRequestSuccess),
            ("testEndRequestUnknownRole", testEndRequestUnknownRole),
            ("testEndRequestCannotMultiplex", testEndRequestCannotMultiplex)
        ]
    }
    
    // Perform a request end test (FCGI_END_REQUEST) with a varying protocol status.
    //
    func executeRequestEnd(protocolStatus: UInt8) {
        do {
            let creator : FastCGIRecordCreate = FastCGIRecordCreate()
            creator.recordType = FastCGI.Constants.FCGI_END_REQUEST
            creator.requestId = 1
            creator.protocolStatus = protocolStatus
            
            let parser : FastCGIRecordParser = FastCGIRecordParser.init(try creator.create())
            let remainingData = try parser.parse()
            
            XCTAssert(remainingData == nil, "Parser returned overflow data where not should have been present")
            XCTAssert(parser.type == FastCGI.Constants.FCGI_END_REQUEST, "Record type received was incorrect")
            XCTAssert(parser.requestId == 1, "Request ID received was incorrect")
            XCTAssert(parser.protocolStatus == protocolStatus, "Protocol status received incorrect.")
            
        }
        catch {
            XCTFail("Exception thrown: \(error)")
        }
    }
    
    // Test an FCGI_END_REQUEST record exchange with FCGI_REQUEST_COMPLETE (done/ok)
    //
    func testEndRequestSuccess() {
        executeRequestEnd(protocolStatus: FastCGI.Constants.FCGI_REQUEST_COMPLETE)
    }
    
    // Test an FCGI_END_REQUEST record exchange with FCGI_UNKNOWN_ROLE (requested role is unknown)
    //
    func testEndRequestUnknownRole() {
        executeRequestEnd(protocolStatus: FastCGI.Constants.FCGI_UNKNOWN_ROLE)
    }

    // Test an FCGI_END_REQUEST record exchange with FCGI_CANT_MPX_CONN (multiplexing not available)
    //
    func testEndRequestCannotMultiplex() {
        executeRequestEnd(protocolStatus: FastCGI.Constants.FCGI_CANT_MPX_CONN)
    }

    // Generate a block of random data for our test suite to use.
    //
    func generateRandomData(_ numberOfBytes: Int) -> Data {
        
        var bytes = [UInt8](repeating: 0, count: numberOfBytes)
        #if os(Linux)
            for index in stride(from: 0, to: numberOfBytes, by: MemoryLayout<CLong>.size) {
                var random : CLong = Glibc.random()
                memcpy(&bytes+index ,&random, MemoryLayout<CLong>.size)
            }
        #else
            Darwin.arc4random_buf(&bytes, numberOfBytes)
        #endif
       
#if swift(>=5.0)
        return Data(bytes)
#else 
        return Data(bytes: bytes)
#endif
    }
    
    // Test an FCGI_STDOUT or FCGI_STDIN exchange with overly large bundle.
    //
    func executeOversizeDataExchangeTest(ofType: UInt8) {
        
        do {
            // 128k worth of data
            let testData = self.generateRandomData(128 * 1024)
            
            let creator : FastCGIRecordCreate = FastCGIRecordCreate()
            creator.recordType = ofType
            creator.requestId = 1
            creator.data = testData
            
            let _ = try creator.create()
            
            XCTFail("Creator allowed the creation of an enormous payload (>64k)")
            
        }
        catch FastCGI.RecordErrors.oversizeData {
            // this is fine - is expected.
        }
        catch {
            XCTFail("Exception thrown: \(error)")
        }
        
    }
    
    // Test an FCGI_STDOUT record exchange with overly large bundle (forbidden)
    //
    func testOversizeDataOutput() {
        executeOversizeDataExchangeTest(ofType: FastCGI.Constants.FCGI_STDOUT)
    }
    
    // Test an FCGI_STDOUT record exchange with overly large bundle (forbidden)
    //
    func testOversizeDataInput() {
        executeOversizeDataExchangeTest(ofType: FastCGI.Constants.FCGI_STDIN)
    }
    
    // Test an FCGI_STDOUT or FCGI_STDIN record exchange
    //
    func executeDataExchangeTest(ofType: UInt8) {
        
        do {
            let testData = self.generateRandomData(32 * 1024)
            
            let creator : FastCGIRecordCreate = FastCGIRecordCreate()
            creator.recordType = ofType
            creator.requestId = 1
            creator.data = testData
            
            let parser : FastCGIRecordParser = FastCGIRecordParser.init(try creator.create())
            let remainingData = try parser.parse()
            
            XCTAssert(remainingData == nil, "Parser returned overflow data where not should have been present")
            XCTAssert(parser.type == ofType, "Record type received was incorrect")
            XCTAssert(parser.requestId == 1, "Request ID received was incorrect")
            XCTAssert(parser.data != nil, "No data was received")
            
            if parser.data != nil {
                XCTAssert(testData == parser.data, "Data received was not data sent.")
            }
            
        }
        catch {
            XCTFail("Exception thrown: \(error)")
        }
        
    }
    
    // Test an FCGI_STDOUT record exchange
    //
    func testDataOutput() {
        executeDataExchangeTest(ofType: FastCGI.Constants.FCGI_STDOUT)
    }

    // Test an FCGI_STDOUT record exchange
    //
    func testDataInput() {
        executeDataExchangeTest(ofType: FastCGI.Constants.FCGI_STDIN)
    }

    // Test to verify that the record creator won't make absurd
    // records. This is a casual test but it ensures basic sanity.
    //
    func testNoRequestId() {
        
        do {
            let creator : FastCGIRecordCreate = FastCGIRecordCreate()
            creator.recordType = FastCGI.Constants.FCGI_STDOUT
            
            var _ = try creator.create()
            
            XCTFail("Record creator allowed record with no record ID to be created.")
        }
        catch FastCGI.RecordErrors.invalidRequestId {
            // ignore this - expected behaviour
        }
        catch {
            XCTFail("Record creator threw unexpected exception")
        }
        
    }
    
    // Test to verify that the record creator won't make absurd
    // records. This is a casual test but it ensures basic sanity.
    //
    func testBadRecordType() {
        
        do {
            let creator : FastCGIRecordCreate = FastCGIRecordCreate()
            creator.recordType = 111 // this is just insane
            creator.requestId = 1
            
             var _ = try creator.create()
            
            XCTFail("Record creator allowed strange record to be created.")
        }
        catch FastCGI.RecordErrors.invalidType {
            // ignore this - expected behaviour
        }
        catch {
            XCTFail("Record creator threw unexpected exception.")
        }
        
    }
    
    // Perform a testRequestBeginXKeepalive() test.
    //
    // This tests to determine if the parser and encoder can create FCGI_BEGIN_REQUEST
    // records that are interoperable.
    //
    func executeRequestBegin(keepalive: Bool) {
        do {
            let creator : FastCGIRecordCreate = FastCGIRecordCreate()
            creator.recordType = FastCGI.Constants.FCGI_BEGIN_REQUEST
            creator.requestId = 1
            creator.requestRole = FastCGI.Constants.FCGI_RESPONDER
            creator.keepAlive = keepalive
            
            let parser : FastCGIRecordParser = FastCGIRecordParser.init(try creator.create())
            let remainingData = try parser.parse()
            
            XCTAssert(remainingData == nil, "Parser returned overflow data where not should have been present")
            XCTAssert(parser.type == FastCGI.Constants.FCGI_BEGIN_REQUEST, "Record type received was incorrect")
            XCTAssert(parser.requestId == 1, "Request ID received was incorrect")
            XCTAssert(parser.role == FastCGI.Constants.FCGI_RESPONDER, "Role received was incorrect")
            XCTAssert(parser.keepalive == keepalive, "Keep alive state was received incorrectly.")
            
        }
        catch {
            XCTFail("Exception thrown: \(error)")
        }
    }
    
    // Test an FCGI_BEGIN_REQUEST record exchange with keep alive requested.
    //
    func testRequestBeginKeepalive() {
        self.executeRequestBegin(keepalive: true)
    }

    // Test an FCGI_BEGIN_REQUEST record exchange WITHOUT keep alive requested.
    //
    func testRequestBeginNoKeepalive() {
        self.executeRequestBegin(keepalive: false)
    }
    
    // Perform a parameter record test.
    //
    // This tests to determine if the parser and encoder can create FCGI_PARAMS
    // records that are interoperable.
    //
    func testParameters() {
        do {
            // Make a long string
            var longString : String = ""
            
            for _ in 1...256 {
                longString = longString + "X"
            }
            
            // create some parameters to tests
            var parameters : [(String,String)] = []
            
            parameters.append(("SHORT_KEY_A", "SHORT_VALUE"))
            parameters.append(("SHORT_KEY_B", "LONG_VALUE_" + longString))
            parameters.append(("LONG_KEY_A_" + longString, "SHORT_VALUE"))
            parameters.append(("LONG_KEY_A_" + longString, "LONG_VALUE_" + longString))
            
            // test sending those parameters
            let creator : FastCGIRecordCreate = FastCGIRecordCreate()
            creator.recordType = FastCGI.Constants.FCGI_PARAMS
            creator.requestId = 1
            
            for currentHeader : (String,String) in parameters {
                creator.parameters.append((currentHeader.0, currentHeader.1))
            }
            
            let parser : FastCGIRecordParser = FastCGIRecordParser.init(try creator.create())
            let remainingData = try parser.parse()
            
            XCTAssert(remainingData == nil, "Parser returned overflow data where not should have been present")
            XCTAssert(parser.type == FastCGI.Constants.FCGI_PARAMS, "Record type received was incorrect")
            XCTAssert(parser.requestId == 1, "Request ID received was incorrect")
            
            // Check what we received was what we expected.
            for sourceHeader : (String,String) in parameters {
                
                var pairReceived : Bool = false
                
                for currentHeader : Dictionary<String,String> in parser.headers {
                    
                    let currentHeaderName : String? = currentHeader["name"]
                    let currentHeaderValue : String? = currentHeader["value"]
                    
                    if currentHeaderName == sourceHeader.0 && currentHeaderValue == sourceHeader.1 {
                        pairReceived = true
                        break
                    }
                    
                }
                
                XCTAssert(pairReceived, "Key \(sourceHeader.0), Value \(sourceHeader.1) sent but not received")
                
            }
                    
        }
        catch {
            XCTFail("Exception thrown: \(error)")
        }
    }

}
