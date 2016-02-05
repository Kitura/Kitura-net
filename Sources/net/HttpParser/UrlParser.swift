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

import sys
import http_parser_helper

import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

public class UrlParser : CustomStringConvertible {

    public var schema: String?
    public var host: String?
    public var path: String?
    public var query: String?
    public var fragment: String?
    public var userinfo: String?
    public var port: UInt16?
    public var queryParams: [String:String] = [:]
    
    
    public var description: String {
        var desc = ""
        
        if let schema = schema {
            desc += "schema: \(schema) "
        }
        if let host = host {
            desc += "host: \(host) "
        }
        if let port = port {
            desc += "port: \(port) "
        }
        if let path = path {
            desc += "path: \(path) "
        }
        if let query = query {
            desc += "query: \(query) "
            desc += "parsed query: \(queryParams) "
        }
        if let fragment = fragment {
            desc += "fragment: \(fragment) "
        }
        if let userinfo = userinfo {
            desc += "userinfo: \(userinfo) "
        }
        
        return desc
    }
    
    
    public init (url: NSData, isConnect: Bool) {
        var parsedUrl = http_parser_url_url()
        memset(&parsedUrl, 0, sizeof(http_parser_url))
        if http_parser_parse_url_url(UnsafePointer<Int8>(url.bytes), url.length, isConnect ? 1 : 0 , &parsedUrl) == 0 {
            let (s, h, ps, p, q, f, u) = parsedUrl.field_data
            schema = getValueFromUrl(url, fieldSet: parsedUrl.field_set, fieldIndex: UInt16(UF_SCHEMA.rawValue), fieldData: s)
            host = getValueFromUrl(url, fieldSet: parsedUrl.field_set, fieldIndex: UInt16(UF_HOST.rawValue), fieldData: h)
            let portString = getValueFromUrl(url, fieldSet: parsedUrl.field_set, fieldIndex: UInt16(UF_PORT.rawValue), fieldData: ps)
            path = getValueFromUrl(url, fieldSet: parsedUrl.field_set, fieldIndex: UInt16(UF_PATH.rawValue), fieldData: p)
            query = getValueFromUrl(url, fieldSet: parsedUrl.field_set, fieldIndex: UInt16(UF_QUERY.rawValue), fieldData: q)
            fragment = getValueFromUrl(url, fieldSet: parsedUrl.field_set, fieldIndex: UInt16(UF_FRAGMENT.rawValue), fieldData: f)
            userinfo = getValueFromUrl(url, fieldSet: parsedUrl.field_set, fieldIndex: UInt16(UF_USERINFO.rawValue), fieldData: u)

            if let _ = portString {
                port = parsedUrl.port
            }
            
            if let query = query {
                let pairs = query.bridge().componentsSeparatedByString("&")
                for pair in pairs {
                    let pairArr = pair.bridge().componentsSeparatedByString("=")
                    if pairArr.count == 2 {
                        queryParams[pairArr[0]] = pairArr[1]
                    }
                }
            }
        }
    }
    
    private func getValueFromUrl(url: NSData, fieldSet: UInt16, fieldIndex: UInt16, fieldData: http_parser_url_field_data) -> String? {
        if fieldSet & (1 << fieldIndex) != 0 {
            let start = Int(fieldData.off)
            let length = Int(fieldData.len)
            let data = NSData(bytes: UnsafeMutablePointer<UInt8>(url.bytes)+start, length: length)
            return StringUtils.fromUtf8String(data)
        }
        return nil
    }

}

