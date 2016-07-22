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

import KituraSys
import CHTTPParser

import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

// MARK: URLParser

public class URLParser : CustomStringConvertible {

    /// 
    /// Schema
    ///
    public var schema: String?

    /// 
    /// Hostname
    ///
    public var host: String?
    
    ///
    /// Path portion of the URL
    ///
    public var path: String?
    
    ///
    /// The entire query portion of the URL
    ///
    public var query: String?
    
    ///
    /// TODO: ???
    ///
    public var fragment: String?
    
    ///
    /// The userid and password if specified in the URL
    ///
    public var userinfo: String?
    
    ///
    /// The port specified, if any, in the URL
    ///
    public var port: UInt16?
    
    ///
    /// The query parameters brokenn out
    ///
    public var queryParameters: [String:String] = [:]
    
    ///
    /// Nicely formatted description of the parsed result
    ///
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
            desc += "parsed query: \(queryParameters) "
        }
        if let fragment = fragment {
            desc += "fragment: \(fragment) "
        }
        if let userinfo = userinfo {
            desc += "userinfo: \(userinfo) "
        }
        
        return desc
    }
    
    
    ///
    /// Initializes a new URLParser instance
    ///
    /// - Parameter url: url to be parsed
    /// - Parameter isConnect: whether or not a connection has been established
    ///
    public init (url: NSData, isConnect: Bool) {
        
        var parsedURL = http_parser_url_url()
        memset(&parsedURL, 0, sizeof(http_parser_url.self))
        
        if http_parser_parse_url_url(UnsafePointer<Int8>(url.bytes), url.length, isConnect ? 1 : 0 , &parsedURL) == 0 {
            
            let (s, h, ps, p, q, f, u) = parsedURL.field_data
            schema = getValueFromURL(url, fieldSet: parsedURL.field_set, fieldIndex: UInt16(UF_SCHEMA.rawValue), fieldData: s)
            host = getValueFromURL(url, fieldSet: parsedURL.field_set, fieldIndex: UInt16(UF_HOST.rawValue), fieldData: h)
            let portString = getValueFromURL(url, fieldSet: parsedURL.field_set, fieldIndex: UInt16(UF_PORT.rawValue), fieldData: ps)
            path = getValueFromURL(url, fieldSet: parsedURL.field_set, fieldIndex: UInt16(UF_PATH.rawValue), fieldData: p)
            query = getValueFromURL(url, fieldSet: parsedURL.field_set, fieldIndex: UInt16(UF_QUERY.rawValue), fieldData: q)
            fragment = getValueFromURL(url, fieldSet: parsedURL.field_set, fieldIndex: UInt16(UF_FRAGMENT.rawValue), fieldData: f)
            userinfo = getValueFromURL(url, fieldSet: parsedURL.field_set, fieldIndex: UInt16(UF_USERINFO.rawValue), fieldData: u)

            if let _ = portString {
                port = parsedURL.port
            }
            
            if let query = query {
                
                let pairs = query.components(separatedBy: "&")
                for pair in pairs {
                    
                    let pairArray = pair.components(separatedBy: "=")
                    if pairArray.count == 2 {
                        queryParameters[pairArray[0]] = pairArray[1]
                    }
                    
                }
                
            }
        }
    }
    
    ///
    /// TODO: ???
    ///
    ///
    private func getValueFromURL(_ url: NSData, fieldSet: UInt16, fieldIndex: UInt16,
        fieldData: http_parser_url_field_data) -> String? {
        
        if fieldSet & (1 << fieldIndex) != 0 {
            let start = Int(fieldData.off)
            let length = Int(fieldData.len)
            let data = NSData(bytes: UnsafeMutablePointer<UInt8>(url.bytes)+start, length: length)
            return StringUtils.fromUtf8String(data)
        }
        
        return nil
        
    }

}

