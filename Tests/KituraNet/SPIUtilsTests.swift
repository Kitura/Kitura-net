import Foundation

import XCTest

@testable import KituraNet

class SPIUtilsTests: XCTestCase {

#if os(Linux)
    typealias Date = NSDate
#endif

    static var allTests : [(String, (SPIUtilsTests) -> () throws -> Void)] {
        return [
            ("testHttpDate", testHttpDate),
        ]
    }

    func testHttpDate() {

        // Fri, 07 Aug 2009 12:34:56 GMT
        let date = Date(timeIntervalSince1970:1249648496)

        let httpDate = SPIUtils.httpDate(date)

        XCTAssertEqual("Fri, 07 Aug 2009 12:34:56 GMT", httpDate, "HTTP Date did not correctly format date")

    }

}