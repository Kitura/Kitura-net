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

import Foundation

// MARK: HTTP

/// A set of helpers for HTTP: status codes mapping, server and client request creation.
public class HTTP {

    /// Mapping of integer HTTP status codes to the String description.
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

    /// Create a new `HTTPServer`.
    ///
    /// - Returns: an instance of `HTTPServer`.
    public static func createServer() -> HTTPServer {
        return HTTPServer()
    }

    /// Create a new `ClientRequest` using URL.
    ///
    /// - Parameter url: URL address for the request.
    /// - Parameter callback: closure to run after the request.
    /// - Returns: a `ClientRequest` instance
    public static func request(_ url: String, callback: @escaping ClientRequest.Callback) -> ClientRequest {
        return ClientRequest(url: url, callback: callback)
    }

    /// Create a new `ClientRequest` using a list of options.
    ///
    /// - Parameter options: a list of `ClientRequest.Options`.
    /// - Parameter callback: closure to run after the request.
    /// - Returns: a `ClientRequest` instance
    public static func request(_ options: [ClientRequest.Options], callback: @escaping ClientRequest.Callback) -> ClientRequest {
        return ClientRequest(options: options, callback: callback)
    }

    /// Create a new `ClientRequest` using URL.
    ///
    /// - Parameter url: URL address for the request.
    /// - Parameter callback: closure to run after the request.
    /// - Returns: a ClientRequest instance.
    ///
    /// - Note: This method will invoke the end function of the `ClientRequest`
    ///        immediately after its creation.
    public static func get(_ url: String, callback: @escaping ClientRequest.Callback) -> ClientRequest {
        let req = ClientRequest(url: url, callback: callback)
        req.end()
        return req
    }

    /// A set of characters that are valid in requests.
    private static let allowedCharacterSet =  NSCharacterSet(charactersIn:"\"#%/<>?@\\^`{|} ").inverted

    /// Transform the URL into escaped characters.
    ///
    /// - note: URLs can only be sent over the Internet using the ASCII character set, so character escaping will
    /// transform unsafe ASCII characters with a '%' followed by two hexadecimal digits.
    public static func escape(url: String) -> String {
        if let escaped = url.addingPercentEncoding(withAllowedCharacters: allowedCharacterSet) {
            return escaped
        }

        return url
    }
}


// MARK HTTPStatusCode

/// HTTP status codes and numbers.
public enum HTTPStatusCode: Int {

    case accepted = 202, badGateway = 502, badRequest = 400, conflict = 409, `continue` = 100, created = 201
    case expectationFailed = 417, failedDependency  = 424, forbidden = 403, gatewayTimeout = 504, gone = 410
    case httpVersionNotSupported = 505, insufficientSpaceOnResource = 419, insufficientStorage = 507
    case internalServerError = 500, lengthRequired = 411, methodFailure = 420, methodNotAllowed = 405
    case movedPermanently = 301, movedTemporarily = 302, multiStatus = 207, multipleChoices = 300
    case networkAuthenticationRequired = 511, noContent = 204, nonAuthoritativeInformation = 203
    case notAcceptable = 406, notFound = 404, notImplemented = 501, notModified = 304, OK = 200
    case partialContent = 206, paymentRequired = 402, preconditionFailed = 412, preconditionRequired = 428
    case proxyAuthenticationRequired = 407, processing = 102, requestHeaderFieldsTooLarge = 431
    case requestTimeout = 408, requestTooLong = 413, requestURITooLong = 414, requestedRangeNotSatisfiable = 416
    case resetContent = 205, seeOther = 303, serviceUnavailable = 503, switchingProtocols = 101
    case temporaryRedirect = 307, tooManyRequests = 429, unauthorized = 401, unprocessableEntity = 422
    case unsupportedMediaType = 415, useProxy = 305, unknown = -1

}
