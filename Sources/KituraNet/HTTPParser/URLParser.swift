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


// MARK: URLParser
#if SR_1901_BUG
public class URLParser : NSURL {

    /// 
    /// Schema
    ///
    public var schema: String? {
        return self.scheme
    }

    ///
    /// The userid and password if specified in the URL
    ///
    @available(*, deprecated: 0.23, message: "use user and password attributes instead")
    
    public var userinfo: String? {
        // both are specified
        if let username = self.user, let password = self.password {
            return username + ":" + password
        }
        // username only
        if let username = self.user {
            return username
        }
        // password only
        if let password = self.user {
            return ":" + password
        }
        return nil
    }
    
    ///
    /// The query parameters broken out
    ///
    public var queryParameters: [String:String] = [:]
    
    ///
    /// Initializes a new URLParser instance
    ///
    /// - Parameter url: url to be parsed
    ///
    public init(url: NSData) {
        
#if os(Linux)
        super.init(string: String(data: url, encoding: NSUTF8StringEncoding) ?? "", relativeToURL: nil)!
#else
        super.init(string: String(data: url as Data, encoding: String.Encoding.utf8) ?? "", relativeTo: nil)!
#endif
        if let query = self.query {
            
            let pairs = query.components(separatedBy: "&")
            for pair in pairs {
                
                let pairArray = pair.components(separatedBy: "=")
                if pairArray.count == 2 {
                    queryParameters[pairArray[0]] = pairArray[1]
                }

            }
        }
    }
    
    ///
    /// Initializes a new URLParser instance
    ///
    /// - Parameter url: url to be parsed
    /// - Parameter isConnect: unused
    ///
    convenience public init(url: NSData, isConnect: Bool) {
        self.init(url: url)
    }

    // NSURL required initializers
    required convenience public init(fileReferenceLiteralResourceName path: String) {
        fatalError("init(fileReferenceLiteralResourceName:) has not been implemented")
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#endif

public class URLParser : CustomStringConvertible {

    private var url: NSURL?

    ///
    /// Schema
    ///
    public var schema: String? {
        return url?.scheme
    }

    ///
    /// Hostname
    ///
    public var host: String? {
        return url?.host
    }

    ///
    /// Path portion of the URL
    ///
    public var path: String? {
        return url?.path
    }

    ///
    /// The entire query portion of the URL
    ///
    public var query: String? {
        return url?.query
    }

    ///
    /// TThe fragment
    ///
    public var fragment: String? {
        return url?.fragment
    }

    ///
    /// The userid and password if specified in the URL
    ///
    @available(*, deprecated: 0.23, message: "use user and password attributes instead")

    public var userinfo: String? {
        // both are specified
        if let username = url?.user, let password = url?.password {
            return username + ":" + password
        }
        // username only
        if let username = url?.user {
            return username
        }
        // password only
        if let password = url?.user {
            return ":" + password
        }
        return nil
    }

    public var user: String? {
        return url?.user
    }

    public var password: String? {
        return url?.password
    }

    ///
    /// The port specified, if any, in the URL
    ///
    public var port: UInt16? {
        return url?.port?.uint16Value
    }

    ///
    /// The query parameters brokenn out
    ///
    public var queryParameters: [String:String] = [:]

    ///
    /// Nicely formatted description of the parsed result
    ///
    public var description: String {
        if let description = url?.description {
            return description
        }
        return ""
    }


    ///
    /// Initializes a new URLParser instance
    ///
    /// - Parameter url: url to be parsed
    /// - Parameter isConnect: whether or not a connection has been established
    ///
    public init (url data: NSData, isConnect: Bool) {

        #if os(Linux)
        url = NSURL(string: String(data: data, encoding: NSUTF8StringEncoding) ?? "", relativeToURL: nil)
        #else
        url = NSURL(string: String(data: data as Data, encoding: String.Encoding.utf8) ?? "", relativeTo: nil)
        #endif
        if let query = url?.query {

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
