/*
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
 */

import CHTTPParser

import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

// MARK: URLParser

/**
 Splits and parses URLs into components - scheme, host, port, path, query string etc. according to the following format:

**scheme:[//[user:password@]host[:port]][/]path[?query][#fragment]**

### Usage Example: ###
````swift
 // Initialize a new URLParser instance, and check whether or not a connection has been established.
 let url = "http://user:password@sample.host.com:8080/a/b/c?query=somestring#hash".data(using: .utf8)!
 let urlParser = URLParser(url: url, isConnect: false)
````
*/
public class URLParser : CustomStringConvertible {

    /// The schema of the URL.
    public var schema: String?

    /// The host component of the URL.
    public var host: String?
    
    /// Path portion of the URL.
    public var path: String?
    
    /// The query component of the URL.
    public var query: String?
    
    /// An optional fragment identifier providing direction to a secondary resource.
    public var fragment: String?
    
    /// The userid and password if specified in the URL.
    public var userinfo: String?
    
    /// The port specified, if any, in the URL.
    public var port: UInt16?
    
    /**
    The value of the query component of the URL name/value pair, for the passed in query name.
    
    ### Usage Example: ###
    ````swift
    let parsedURLParameters = urlParser.queryParameters["query"]
    ````
    */
    public var queryParameters: [String:String] = [:]
    
    /**
    Nicely formatted description of the parsed result.
    
    ### Usage Example: ###
    ````swift
    let parsedURLDescription = urlParser.description
    ````
    */
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
    
    /**
    Initialize a new `URLParser` instance.
    
    - Parameter url: The URL to be parsed.
    - Parameter isConnect: A boolean, indicating whether or not a connection has been established.
    
    ### Usage Example: ###
    ````swift
    let parsedURL = URLParser(url: someURL, isConnect: false)
    ````
    */
    public init (url: Data, isConnect: Bool) {
        
        var parsedURL = http_parser_url_url()
        memset(&parsedURL, 0, MemoryLayout<http_parser_url>.size)
        
        let cIsConnect: Int32 = (isConnect ? 1 : 0)
#if swift(>=5.0)
        let returnCode = url.withUnsafeBytes() { (bytes: UnsafeRawBufferPointer) -> Int32 in
            return http_parser_parse_url_url(bytes.bindMemory(to: Int8.self).baseAddress, url.count, cIsConnect, &parsedURL)
        }
#else
        let returnCode = url.withUnsafeBytes() { (bytes: UnsafePointer<Int8>) -> Int32 in
            return http_parser_parse_url_url(bytes, url.count, cIsConnect, &parsedURL)
        }
#endif
        
        guard returnCode == 0  else { return }
            
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
            let pairs = query.split(separator: "&")
            for pair in pairs {
                let pairArray = pair.split(separator: "=")
                if pairArray.count == 2 {
                    queryParameters[String(pairArray[0])] = String(pairArray[1])
                }
            }
        }
    }
    
    ///
    /// TODO: ???
    ///
    ///
    private func getValueFromURL(_ url: Data, fieldSet: UInt16, fieldIndex: UInt16,
        fieldData: http_parser_url_field_data) -> String? {
        
        if fieldSet & (1 << fieldIndex) != 0 {
            let start = Int(fieldData.off)
            let length = Int(fieldData.len)
            let data = url.subdata(in: start..<start+length)
            return String(data: data, encoding: .utf8)
        }
        
        return nil
    }
}

