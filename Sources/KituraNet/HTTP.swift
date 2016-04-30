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

// MARK: HTTP

public class HTTP {
    
    ///
    /// Mapping of integer status codes to the String description
    ///
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
        419: "Insufficient Space on Resource", 420: "Method Failure", 422: "Unprocessable Entity",
        424: "Failed Dependency", 428: "Precondition Required", 429: "Too Many Requests",
        431: "Request Header Fields Too Large",
        500: "Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable",
        504: "Gateway Timeout", 505: "HTTP Version Not Supported", 507: "Insufficient Storage",
        511: "Network Authentication Required"
    ]
    
    ///
    /// Creates a new HTTP server
    /// 
    /// - Returns: an instance of HTTPServer
    ///
    public static func createServer() -> HTTPServer {
        
        return HTTPServer()
        
    }
    
    ///
    /// Creates a new ClientRequest using URL
    ///
    /// - Parameter url: URL address for the request
    /// - Parameter callback: closure to run after the request
    ///
    /// - Returns: a ClientRequest instance
    ///
    public static func request(_ url: String, callback: ClientRequestCallback) -> ClientRequest {
        
        return ClientRequest(url: url, callback: callback)
        
    }
    
    ///
    /// Creates a new ClientRequest using a list of options
    ///
    /// - Parameter options: a list of ClientRequestOptions
    /// - Parameter callback: closure to run after the request
    ///
    /// - Returns: a ClientRequest instance
    ///
    public static func request(_ options: [ClientRequestOptions], callback: ClientRequestCallback) -> ClientRequest {
        
        return ClientRequest(options: options, callback: callback)
        
    }
    
    ///
    /// Creates a new ClientRequest using URL
    /// *Note*: This method will end the ClientRequest immediately after creation
    ///
    /// - Parameter url: URL address for the request
    /// - Parameter callback: closure to run after the request 
    ///
    /// - Returns: a ClientRequest instance
    ///
    public static func get(_ url: String, callback: ClientRequestCallback) -> ClientRequest {
        
        let req = ClientRequest(url: url, callback: callback)
        req.end()
        return req
        
    }

    ///
    /// A set of characters that are valid in requests
    ///
    #if os(Linux)
    private static let allowedCharacterSet =  NSCharacterSet(charactersInString:"\"#%/<>?@\\^`{|}").invertedSet
    #else
    private static let allowedCharacterSet =  NSCharacterSet(charactersIn:"\"#%/<>?@\\^`{|}").inverted
    #endif
    
    ///
    /// Transform the URL into escaped characters
    /// 
    /// *Note*: URLS can only be sent over the Internet using the ASCII character set, so character escaping will
    /// transform unsafe ASCII characters with a '%' followed by two hexadecimal digits.
    ///
    public static func escapeUrl(_ url: String) -> String {
        
        #if os(Linux)
        if let escaped = url.bridge().stringByAddingPercentEncodingWithAllowedCharacters(allowedCharacterSet) {
            return escaped
        }
        #else
        if let escaped = url.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) {
            return escaped
        }
        #endif
        
        return url
    }
}


///
/// HTTP status codes and numbers
///
public enum HTTPStatusCode: Int {
    
    case Accepted = 202, BadGateway = 502, BadRequest = 400, Conflict = 409, Continue = 100, Created = 201
    case ExpectationFailed = 417, FailedDependency  = 424, Forbidden = 403, GatewayTimeout = 504, Gone = 410
    case HTTPVersionNotSupported = 505, InsufficientSpaceOnResource = 419, InsufficientStorage = 507
    case InternalServerError = 500, LengthRequired = 411, MethodFailure = 420, MethodNotAllowed = 405
    case MovedPermanently = 301, MovedTemporarily = 302, MultiStatus = 207, MultipleChoices = 300
    case NetworkAuthenticationRequired = 511, NoContent = 204, NonAuthoritativeInformation = 203
    case NotAcceptable = 406, NotFound = 404, NotImplemented = 501, NotModified = 304, OK = 200
    case PartialContent = 206, PaymentRequired = 402, PreconditionFailed = 412, PreconditionRequired = 428
    case ProxyAuthenticationRequired = 407, Processing = 102, RequestHeaderFieldsTooLarge = 431
    case RequestTimeout = 408, RequestTooLong = 413, RequestURITooLong = 414, RequestedRangeNotSatisfiable = 416
    case ResetContent = 205, SeeOther = 303, ServiceUnavailable = 503, SwitchingProtocols = 101
    case TemporaryRedirect = 307, TooManyRequests = 429, Unauthorized = 401, UnprocessableEntity = 422
    case UnsupportedMediaType = 415, UseProxy = 305, Unknown = -1
    
}
