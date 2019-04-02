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

/* 
 * This source file includes content derived from the Swift.org Server APIs open source project
 * (http://github.com/swift-server/http)
 *
 * Copyright (c) 2017 Swift Server API project authors
 * Licensed under Apache License v2.0 with Runtime Library Exception
 *
 * See http://swift.org/LICENSE.txt for license information
 */

import Foundation

// MARK: HTTP

/**
A set of helpers for HTTP: status codes mapping, server and client request creation.

### Usage Example: ###
````swift
 //Create a HTTP server.
 let server = HTTP.createServer()
 
 //Create a new a `ClientRequest` instance using a URL.
 let request = HTTP.request("http://localhost/8080") {response in
 ...
 }
 
 //Get a `ClientRequest` instance from a URL.
 let getHTTP = HTTP.get("http://localhost/8080") { response in
 ...
 }
 
 HTTP.escape(url: testString)
````
*/
public class HTTP {
    
    /**
     Mapping of integer HTTP status codes to the String description.
    
    ### Usage Example: ###
    ````swift
     var statusText = HTTP.statusCodes[HTTPStatusCode.OK.rawValue]
    ````
    */
    public static let statusCodes = [
        
        100: "Continue", 101: "Switching Protocols", 102: "Processing",
        200: "OK", 201: "Created", 202: "Accepted", 203: "Non Authoritative Information",
        204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status",
        300: "Multiple Choices", 301: "Moved Permanently", 302: "Moved Temporarily", 303: "See Other",
        304: "Not Modified", 305: "Use Proxy", 307: "Temporary Redirect",
        400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required",
        408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required",
        412: "Precondition Failed", 413: "Request Entity Too Large", 414: "Request-URI Too Long",
        415: "Unsupported Media Type", 416: "Requested Range Not Satisfiable", 417: "Expectation Failed",
        419: "Insufficient Space on Resource", 420: "Method Failure", 421: "Misdirected Request",
        422: "Unprocessable Entity", 424: "Failed Dependency", 428: "Precondition Required",
        429: "Too Many Requests", 431: "Request Header Fields Too Large",
        500: "Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable",
        504: "Gateway Timeout", 505: "HTTP Version Not Supported", 507: "Insufficient Storage",
        511: "Network Authentication Required"
    ]
    
    /**
    Create a new `HTTPServer`.
    
    - Returns: an instance of `HTTPServer`.
    
    ### Usage Example: ###
    ````swift
    let server = HTTP.createServer()
    ````
    */
    public static func createServer() -> HTTPServer {
        return HTTPServer()
    }
    
    /**
    Create a new `ClientRequest` using URL.
    
    - Parameter url: URL address for the request.
    - Parameter callback: closure to run after the request.
    - Returns: a `ClientRequest` instance
    
    ### Usage Example: ###
    ````swift
     let request = HTTP.request("http://localhost/8080") {response in
         ...
     }
    ````
    */
    public static func request(_ url: String, callback: @escaping ClientRequest.Callback) -> ClientRequest {
        return ClientRequest(url: url, callback: callback)
    }
    
    /**
    Create a new `ClientRequest` using a list of options.
    
    - Parameter options: a list of `ClientRequest.Options`.
    - Parameter unixDomainSocketPath: the path of a Unix domain socket that this client should connect to (defaults to `nil`).
    - Parameter callback: The closure to run after the request completes. The `ClientResponse?` parameter allows access to the response from the server.
    - Returns: a `ClientRequest` instance
    
    ### Usage Example: ###
    ````swift
     let myOptions: [ClientRequest.Options] = [.hostname("localhost"), .port("8080")]
    let request = HTTP.request(myOptions) { response in
        // Process the ClientResponse
    }
    ````
    */
    public static func request(_ options: [ClientRequest.Options], unixDomainSocketPath: String? = nil, callback: @escaping ClientRequest.Callback) -> ClientRequest {
        return ClientRequest(options: options, unixDomainSocketPath: unixDomainSocketPath, callback: callback)
    }
    
    /**
    Get a `ClientRequest` using URL.
    
    - Parameter url: URL address for the request.
    - Parameter callback: closure to run after the request.
    - Returns: a ClientRequest instance.
    
    - Note: This method will invoke the end function of the `ClientRequest`
           immediately after its creation.
    
    ### Usage Example: ###
    ````swift
     let request = HTTP.get("http://localhost/8080") { response in
         ...
     }
    ````
    */
    public static func get(_ url: String, callback: @escaping ClientRequest.Callback) -> ClientRequest {
        let req = ClientRequest(url: url, callback: callback)
        req.end()
        return req
    }
    
    /// A set of characters that are valid in requests.
    private static let allowedCharacterSet =  NSCharacterSet(charactersIn:"\"#%/<>?@\\^`{|} ").inverted
    
    /**
    Transform the URL into escaped characters.
    
    - note: URLs can only be sent over the Internet using the ASCII character set, so character escaping will
    transform unsafe ASCII characters with a '%' followed by two hexadecimal digits.
    
    ### Usage Example: ###
    ````swift
    HTTP.escape(url: testString)
    ````
    */
    public static func escape(url: String) -> String {
        if let escaped = url.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) {
            return escaped
        }
        
        return url
    }
}


// MARK HTTPStatusCode

/**
HTTP status codes and numbers.

### Usage Example: ###
````swift
var httpStatusCode: HTTPStatusCode = .unknown
````
*/
public enum HTTPStatusCode: Int {
    /// HTTP code 202
    case accepted = 202,
    /// HTTP code 502
    badGateway = 502,
    /// HTTP code 400
    badRequest = 400,
    /// HTTP code 409
    conflict = 409,
    /// HTTP code 100
    `continue` = 100,
    /// HTTP code 201
    created = 201
    /// HTTP code 417
    case expectationFailed = 417,
    /// HTTP code 424
    failedDependency  = 424,
    /// HTTP code 403
    forbidden = 403,
    /// HTTP code 504
    gatewayTimeout = 504,
    /// HTTP code 410
    gone = 410
    /// HTTP code 505
    case httpVersionNotSupported = 505,
    /// HTTP code 419
    insufficientSpaceOnResource = 419,
    /// HTTP code 507
    insufficientStorage = 507
    /// HTTP code 500
    case internalServerError = 500,
    /// HTTP code 411
    lengthRequired = 411,
    /// HTTP code 420
    methodFailure = 420,
    /// HTTP code 405
    methodNotAllowed = 405
    /// HTTP code 301
    case movedPermanently = 301,
    /// HTTP code 302
    movedTemporarily = 302,
    /// HTTP code 207
    multiStatus = 207,
    /// HTTP code 300
    multipleChoices = 300
    /// HTTP code 511
    case networkAuthenticationRequired = 511,
    /// HTTP code 204
    noContent = 204,
    /// HTTP code 203
    nonAuthoritativeInformation = 203
    /// HTTP code 406
    case notAcceptable = 406,
    /// HTTP code 404
    notFound = 404,
    /// HTTP code 501
    notImplemented = 501,
    /// HTTP code 304
    notModified = 304,
    /// HTTP code 200
    OK = 200
    /// HTTP code 206
    case partialContent = 206,
    /// HTTP code 402
    paymentRequired = 402,
    /// HTTP code 412
    preconditionFailed = 412,
    /// HTTP code 428
    preconditionRequired = 428
    /// HTTP code 407
    case proxyAuthenticationRequired = 407,
    /// HTTP code 102
    processing = 102,
    /// HTTP code 431
    requestHeaderFieldsTooLarge = 431
    /// HTTP code 408
    case requestTimeout = 408,
    /// HTTP code 413
    requestTooLong = 413,
    /// HTTP code 414
    requestURITooLong = 414,
    /// HTTP code 416
    requestedRangeNotSatisfiable = 416
    /// HTTP code 205
    case resetContent = 205,
    /// HTTP code 303
    seeOther = 303,
    /// HTTP code 503
    serviceUnavailable = 503,
    /// HTTP code 101
    switchingProtocols = 101
    /// HTTP code 307
    case temporaryRedirect = 307,
    /// HTTP code 429
    tooManyRequests = 429,
    /// HTTP code 401
    unauthorized = 401,
    /// HTTP code 422
    unprocessableEntity = 422
    /// HTTP code 415
    case unsupportedMediaType = 415,
    /// HTTP code 305
    useProxy = 305,
    /// HTTP code 421
    misdirectedRequest = 421,
    /// HTTP code -1
    unknown = -1
    
}


extension HTTPStatusCode {
    
    /// The class of a `HTTPStatusCode` code
    /// - See: https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml for more information
    public enum Class {
        /// Informational: the request was received, and is continuing to be processed
        case informational
        /// Success: the action was successfully received, understood, and accepted
        case successful
        /// Redirection: further action must be taken in order to complete the request
        case redirection
        /// Client Error: the request contains bad syntax or cannot be fulfilled
        case clientError
        /// Server Error: the server failed to fulfill an apparently valid request
        case serverError
        /// Invalid: the code does not map to a well known status code class
        case invalidStatus
        
        init(code: Int) {
            switch code {
            case 100..<200: self = .informational
            case 200..<300: self = .successful
            case 300..<400: self = .redirection
            case 400..<500: self = .clientError
            case 500..<600: self = .serverError
            default: self = .invalidStatus
            }
        }
    }
    
    /// The `Class` representing the class of status code for this response status
    public var `class`: Class {
        return Class(code: self.rawValue)
    }
}

