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

class ParserTests: KituraNetTest {
    static var allTests : [(String, (ParserTests) -> () throws -> Void)] {
        return [
            ("testParseComplexUrl", testParseComplexUrl),
            ("testParserDescription", testParserDescription),
            ("testParseSimpleUrl", testParseSimpleUrl)
        ]
    }
    
    func testParseSimpleUrl() {
        let url = "https://example.org/absolute/URI/with/absolute/path/to/resource.txt".data(using: .utf8)!
        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema, "https", "Incorrect schema")
        XCTAssertEqual(urlParser.host, "example.org", "Incorrect host")
        XCTAssertEqual(urlParser.path, "/absolute/URI/with/absolute/path/to/resource.txt", "Incorrect path")
    }
    
    func testParseComplexUrl() {
        let url = "abc://username:password@example.com:123/path/data?key=value&key1=value1#fragid1".data(using: .utf8)!
        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema, "abc", "Incorrect schema")
        XCTAssertEqual(urlParser.host, "example.com", "Incorrect host")
        XCTAssertEqual(urlParser.path, "/path/data", "Incorrect path")
        XCTAssertEqual(urlParser.port, 123, "Incorrect port")
        XCTAssertEqual(urlParser.fragment, "fragid1", "Incorrect fragment")
        XCTAssertEqual(urlParser.userinfo, "username:password", "Incorrect userinfo")
        XCTAssertEqual(urlParser.queryParameters["key"], "value", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"], "value1", "Incorrect query")
    }
    
    func testParserDescription() {
        let url = "abc://username:password@example.com:123/path/data?key=value#fragid1".data(using: .utf8)!
        let urlParser = URLParser(url: url, isConnect: false)
        
        let expectedString = "schema: abc host: example.com port: 123 path: /path/data " +
                                  "query: key=value parsed query: [\"key\": \"value\"] " +
                                  "fragment: fragid1 userinfo: username:password "
        
        XCTAssertEqual(urlParser.description, expectedString, "URLParser.description equaled [\(urlParser.description)]. It should have equaled [\(expectedString)]")
    }
}
