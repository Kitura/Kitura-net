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

public class Http {
    
    public static let statusCodes = [
        100: "Continue", 101: "Switching Protocols", 102: "Processing",
        200: "OK", 201: "Created", 202: "Accepted", 203: "Non Authoritative Information", 204: "No Content",
                   205: "Reset Content", 206: "Partial Content", 207: "Multi-Status",
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
    
    public static func createServer() -> HttpServer {
        return HttpServer()
    }
    
    public static func request(url: String, callback: ClientRequestCallback) -> ClientRequest {
        return ClientRequest(url: url, callback: callback)
    }
    
    public static func request(options: [ClientRequestOptions], callback: ClientRequestCallback) -> ClientRequest {
        return ClientRequest(options: options, callback: callback)
    }
    
    public static func get(url: String, callback: ClientRequestCallback) -> ClientRequest {
        let req = ClientRequest(url: url, callback: callback)
        req.end()
        return req
    }

    private static let allowedCharacterSet =  NSCharacterSet(charactersInString:"\"#%/<>?@\\^`{|}").invertedSet
    
    public static func escapeUrl(url: String) -> String {
        if let escaped = url.bridge().stringByAddingPercentEncodingWithAllowedCharacters(allowedCharacterSet) {
            return escaped
        }
        return url
    }
}



public enum HttpStatusCode: Int {
    case ACCEPTED = 202, BAD_GATEWAY = 502, BAD_REQUEST = 400, CONFLICT = 409, CONTINUE = 100, CREATED = 201
    case EXPECTATION_FAILED = 417, FAILED_DEPENDENCY  = 424, FORBIDDEN = 403, GATEWAY_TIMEOUT = 504, GONE = 410
    case HTTP_VERSION_NOT_SUPPORTED = 505, INSUFFICIENT_SPACE_ON_RESOURCE = 419, INSUFFICIENT_STORAGE = 507
    case INTERNAL_SERVER_ERROR = 500, LENGTH_REQUIRED = 411, METHOD_FAILURE = 420, METHOD_NOT_ALLOWED = 405
    case MOVED_PERMANENTLY = 301, MOVED_TEMPORARILY = 302, MULTI_STATUS = 207, MULTIPLE_CHOICES = 300
    case NETWORK_AUTHENTICATION_REQUIRED = 511, NO_CONTENT = 204, NON_AUTHORITATIVE_INFORMATION = 203
    case NOT_ACCEPTABLE = 406, NOT_FOUND = 404, NOT_IMPLEMENTED = 501, NOT_MODIFIED = 304, OK = 200
    case PARTIAL_CONTENT = 206, PAYMENT_REQUIRED = 402, PRECONDITION_FAILED = 412, PRECONDITION_REQUIRED = 428
    case PROXY_AUTHENTICATION_REQUIRED = 407, PROCESSING = 102, REQUEST_HEADER_FIELDS_TOO_LARGE = 431
    case REQUEST_TIMEOUT = 408, REQUEST_TOO_LONG = 413, REQUEST_URI_TOO_LONG = 414, REQUESTED_RANGE_NOT_SATISFIABLE = 416
    case RESET_CONTENT = 205, SEE_OTHER = 303, SERVICE_UNAVAILABLE = 503, SWITCHING_PROTOCOLS = 101
    case TEMPORARY_REDIRECT = 307, TOO_MANY_REQUESTS = 429, UNAUTHORIZED = 401, UNPROCESSABLE_ENTITY = 422
    case UNSUPPORTED_MEDIA_TYPE = 415, USE_PROXY = 305, UNKNOWN = -1
}
