/**
 * Copyright IBM Corporation 2017
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

// Test disabled on Swift 4 for now due to
// https://bugs.swift.org/browse/SR-5684

#if os(OSX) && !swift(>=3.2)
    import XCTest
    
    class VerifyLinuxTestCount: XCTestCase {
        func testVerifyLinuxTestCount() {
            var linuxCount: Int
            var darwinCount: Int
            
            // ClientE2ETests
            linuxCount = ClientE2ETests.allTests.count
            darwinCount = Int(ClientE2ETests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from ClientE2ETests.allTests")
            
            // ClientRequestTests
            linuxCount = ClientRequestTests.allTests.count
            darwinCount = Int(ClientRequestTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from ClientRequestTests.allTests")
            
            // FastCGIProtocolTests
            linuxCount = FastCGIProtocolTests.allTests.count
            darwinCount = Int(FastCGIProtocolTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from FastCGIProtocolTests.allTests")
            
            // FastCGIRequestTests
            linuxCount = FastCGIRequestTests.allTests.count
            darwinCount = Int(FastCGIRequestTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from FastCGIRequestTests.allTests")
            
            // HTTPResponseTests
            linuxCount = HTTPResponseTests.allTests.count
            darwinCount = Int(HTTPResponseTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from HTTPResponseTests.allTests")
            
            // LargePayloadTests
            linuxCount = LargePayloadTests.allTests.count
            darwinCount = Int(LargePayloadTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from LargePayloadTests.allTests")
            
            // LifecycleListenerTests
            linuxCount = LifecycleListenerTests.allTests.count
            darwinCount = Int(LifecycleListenerTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from LifecycleListenerTests.allTests")
            
            // MiscellaneousTests
            linuxCount = MiscellaneousTests.allTests.count
            darwinCount = Int(MiscellaneousTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from MiscellaneousTests.allTests")
            
            // MonitoringTests
            linuxCount = MonitoringTests.allTests.count
            darwinCount = Int(MonitoringTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from MonitoringTests.allTests")
            
            // ParserTests
            linuxCount = ParserTests.allTests.count
            darwinCount = Int(ParserTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from ParserTests.allTests")
            
            // SocketManagerTests
            linuxCount = SocketManagerTests.allTests.count
            darwinCount = Int(SocketManagerTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from SocketManagerTests.allTests")
            
            // UpgradeTests
            linuxCount = UpgradeTests.allTests.count
            darwinCount = Int(UpgradeTests.defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount, "\(darwinCount - linuxCount) tests are missing from UpgradeTests.allTests")
        }
    }
#endif
