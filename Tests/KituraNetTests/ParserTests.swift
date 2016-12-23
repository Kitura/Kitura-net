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

class ParserTests: XCTestCase {
    static var allTests : [(String, (ParserTests) -> () throws -> Void)] {
        return [
            ("testParseSimpleUrl", testParseSimpleUrl),
            ("testParseComplexUrl", testParseComplexUrl),
            ("testParseUrlWithComplexQueryDictionary", testParseUrlWithComplexQueryDictionary),
            ("testParseUrlWithComplexQueryArray", testParseUrlWithComplexQueryArray),
            ("testParseUrlWithComplexQueryArrayAndDictionary", testParseUrlWithComplexQueryArrayAndDictionary),
            ("testParseUrlWithReplacing", testParseUrlWithReplacing)
        ]
    }

    func testParseSimpleUrl() {
        let url = "https://example.org/absolute/URI/with/absolute/path/to/resource.txt".data(using: .utf8)!
        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema!, "https", "Incorrect schema")
        XCTAssertEqual(urlParser.host!, "example.org", "Incorrect host")
        XCTAssertEqual(urlParser.path!, "/absolute/URI/with/absolute/path/to/resource.txt", "Incorrect path")
    }

    func testParseComplexUrl() {
        let url = "abc://username:password@example.com:123/path/data?key=value&key1=value1#fragid1".data(using: .utf8)!
        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema!, "abc", "Incorrect schema")
        XCTAssertEqual(urlParser.host!, "example.com", "Incorrect host")
        XCTAssertEqual(urlParser.path!, "/path/data", "Incorrect path")
        XCTAssertEqual(urlParser.port!, 123, "Incorrect port")
        XCTAssertEqual(urlParser.fragment!, "fragid1", "Incorrect fragment")
        XCTAssertEqual(urlParser.userinfo!, "username:password", "Incorrect userinfo")
        XCTAssertEqual(urlParser.queryParameters["key"].string, "value", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"].string, "value1", "Incorrect query")
    }

    func testParseUrlWithComplexQueryDictionary() {
        let urlString = "https://example.org/path/data?key=value&key1=10&" +
            "key2[sub]=0&key2[sub1]=true&" +
            "emptyKey1=&" +
            "key3[\"sub\"][sub1][\"sub2\"]=\"text\"&" +
            "emptyKey2="

        let url = urlString.data(using: .utf8)!

        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema!, "https", "Incorrect schema")
        XCTAssertEqual(urlParser.host!, "example.org", "Incorrect host")
        XCTAssertEqual(urlParser.path!, "/path/data", "Incorrect path")

        XCTAssertEqual(urlParser.queryParameters["key"].string, "value", "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key1"].string, "10", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"].int, 10, "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key2"]["sub"].string, "0", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key2"]["sub"].int, 0, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key2", "sub"].string, "0", "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key2"]["sub1"].string, "true", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key2"]["sub1"].bool, true, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key2", "sub1"].string, "true", "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key3"]["sub"]["sub1"]["sub2"].string, "\"text\"", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key3", "sub", "sub1", "sub2"].string, "\"text\"", "Incorrect query")

        XCTAssertNil(urlParser.queryParameters["nonexisting"]["sub"]["sub1"]["sub2"].string, "Wrong nonexisting key")

        XCTAssertEqual(urlParser.queryParameters.dictionary?.count, 4, "Incorrect query")
    }

    func testParseUrlWithComplexQueryArray() {

        let urlString = "https://example.org/path/data?" +
            "key[]=10&key[]=15&key[]=20&" +
            "emptyKey1=&" +
            "key1[][]=101&key1[][]=102&key1[]=103&" +
            "emptyKey2="

        let url = urlString.data(using: .utf8)!

        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema!, "https", "Incorrect schema")
        XCTAssertEqual(urlParser.host!, "example.org", "Incorrect host")
        XCTAssertEqual(urlParser.path!, "/path/data", "Incorrect path")

        XCTAssertEqual(urlParser.queryParameters["key"].array?.count, 3, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key"][0].int, 10, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key"][1].int, 15, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key"][2].int, 20, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key"][3].int, nil, "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key1"][0].array?.count, 2, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"][0][0].int, 101, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"][0][1].int, 102, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"][1].int, 103, "Incorrect query")

        XCTAssertNil(urlParser.queryParameters["nonexisting"]["sub"]["sub1"]["sub2"].string, "Wrong nonexisting key")

        XCTAssertEqual(urlParser.queryParameters.dictionary?.count, 2, "Incorrect query")
    }

    func testParseUrlWithComplexQueryArrayAndDictionary() {

        let urlString = "https://example.org/path/data?" +
            "key[sub][]=1&key[sub][]=2&key[sub][]=3&" +
            "emptyKey1=&" +
            "key1[sub][][]=101&key1[sub][][]=102&" +
            "key2[][a]=text1&key2[][b]=text2&" +
            "key3[][][a]=text1&key3[][][b]=text2&" +
            "emptyKey2="

        let url = urlString.data(using: .utf8)!

        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema!, "https", "Incorrect schema")
        XCTAssertEqual(urlParser.host!, "example.org", "Incorrect host")
        XCTAssertEqual(urlParser.path!, "/path/data", "Incorrect path")

        XCTAssertEqual(urlParser.queryParameters["key"]["sub"].array?.count, 3, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key"]["sub"][0].int, 1, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key"]["sub"][1].int, 2, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key"]["sub"][2].int, 3, "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key1"]["sub"].array?.count, 1, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"]["sub"][0].array?.count, 2, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"]["sub"][0][0].int, 101, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key1"]["sub"][0][1].int, 102, "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key2"].array?.count, 1, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key2"][0]["a"].string, "text1", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key2"][0]["b"].string, "text2", "Incorrect query")

        XCTAssertEqual(urlParser.queryParameters["key3"][0].array?.count, 1, "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key3"][0][0]["a"].string, "text1", "Incorrect query")
        XCTAssertEqual(urlParser.queryParameters["key3"][0][0]["b"].string, "text2", "Incorrect query")

        XCTAssertNil(urlParser.queryParameters["nonexisting"]["sub"]["sub1"]["sub2"].string, "Wrong nonexisting key")

        XCTAssertEqual(urlParser.queryParameters.dictionary?.count, 4, "Incorrect query")
    }

    func testParseUrlWithReplacing() {
        let urlString = "https://example.org/path/data?" +
            "key[sub][]=1&key[sub][]=2&key[sub][]=3&" +
            "key[sub]=0"

        let url = urlString.data(using: .utf8)!

        let urlParser = URLParser(url: url, isConnect: false)
        XCTAssertEqual(urlParser.schema!, "https", "Incorrect schema")
        XCTAssertEqual(urlParser.host!, "example.org", "Incorrect host")
        XCTAssertEqual(urlParser.path!, "/path/data", "Incorrect path")

        XCTAssertEqual(urlParser.queryParameters["key"]["sub"].int, 0, "Incorrect query")
    }
}
