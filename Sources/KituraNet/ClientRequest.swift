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

import LoggerAPI
import CCurl
import Socket

import Foundation

// MARK: ClientRequest

/// This class provides a set of low level APIs for issuing HTTP requests to another server.
public class ClientRequest {

    /// Initialize the one time initialization struct to cause one time initializations to occur
    static private let oneTime = OneTimeInitializations()
    
    /// The set of HTTP headers to be sent with the request.
    public var headers = [String: String]()
    
    /// The URL for the request
    public private(set) var url: String = ""
    
    /// The HTTP method (i.e. GET, POST, PUT, DELETE) for the request
    public private(set) var method: String = "get"
    
    /// The username to be used if using Basic Auth authentication
    public private(set) var userName: String?
    
    /// The password to be used if using Basic Auth authentication.
    public private(set) var password: String?

    /// The maximum number of redirects before failure.
    ///
    /// - Note: The `ClientRequest` class will automatically follow redirect responses. To
    ///        avoid redirect loops, it will at maximum follow `maxRedirects` redirects.
    public private(set) var maxRedirects = 10
    
    /// If true, the "Connection: close" header will be added to the request that is sent.
    public private(set) var closeConnection = false

    /// Handle for working with libCurl
    private var handle: UnsafeMutableRawPointer?
    
    /// List of header information
    private var headersList: UnsafeMutablePointer<curl_slist>?
    
    /// BufferList to store bytes to be written
    fileprivate var writeBuffers = BufferList()

    /// Response instance for communicating with client
    fileprivate var response: ClientResponse?
    
    /// The callback to receive the response
    private var callback: Callback
    
    /// Should SSL verification be disabled
    private var disableSSLVerification = false
    
    /// Client request option enum
    public enum Options {
        
        /// Specifies the HTTP method (i.e. PUT, POST...) to be sent in the request
        case method(String)
        
        /// Specifies the schema (i.e. HTTP, HTTPS) to be used in the URL of request
        case schema(String)
        
        /// Specifies the host name to be used in the URL of request
        case hostname(String)
        
        /// Specifies the port to be used in the URL of request
        case port(Int16)
        
        /// Specifies the path to be used in the URL of request
        case path(String)
        
        /// Specifies the HTTP headers to be sent with the request
        case headers([String: String])
        
        /// Specifies the user name to be sent with the request, when using basic auth authentication
        case username(String)
        
        /// Specifies the password to be sent with the request, when using basic auth authentication
        case password(String)
        
        /// Specifies the maximum number of redirect responses that will be followed (i.e. re-issue the
        /// request to the location received in the redirect response)
        case maxRedirects(Int)
        
        /// If present, the SSL credentials of the remote server will not be verified.
        ///
        /// - Note: This is very useful when working with self signed certificates.
        case disableSSLVerification
        
    }
    
    /// Response callback closure type
    ///
    /// - Parameter ClientResponse: The `ClientResponse` object that describes the response
    ///                            that was received from the remote server.
    public typealias Callback = (ClientResponse?) -> Void

    /// Initializes a `ClientRequest` instance
    ///
    /// - Parameter url: url for the request 
    /// - Parameter callback: The closure of type `Callback` to be used for the callback.
    init(url: String, callback: @escaping Callback) {
        
        self.url = url
        self.callback = callback
        
    }

    /// Initializes a `ClientRequest` instance
    ///
    /// - Parameter options: An array of `Options' describing the request
    /// - Parameter callback: The closure of type `Callback` to be used for the callback.
    init(options: [Options], callback: @escaping Callback) {

        self.callback = callback

        var theSchema = "http://"
        var hostName = "localhost"
        var path = ""
        var port = ""

        for option in options  {
            switch(option) {

                case .method, .headers, .maxRedirects, .disableSSLVerification:
                    // call set() for Options that do not construct the URL
                    set(option)
                case .schema(var schema):
                    if !schema.contains("://") && !schema.isEmpty {
                      schema += "://"
                    }
                    theSchema = schema
                case .hostname(let host):
                    hostName = host
                case .port(let thePort):
                    port = ":\(thePort)"
                case .path(var thePath):
                    if thePath.characters.first != "/" {
                      thePath = "/" + thePath
                    }
                    path = thePath
                case .username(let userName):
                    self.userName = userName
                case .password(let password):
                    self.password = password
            }
        }

        // Adding support for Basic HTTP authentication
        let user = self.userName ?? ""
        let pwd = self.password ?? ""
        var authenticationClause = ""
        // If either the userName or password are non-empty, add the authenticationClause
        if (!user.isEmpty || !pwd.isEmpty) {
          authenticationClause = "\(user):\(pwd)@"
        }

        url = "\(theSchema)\(authenticationClause)\(hostName)\(port)\(path)"

    }

    /// Set a single option in the request.  URL parameters must be set in init()
    ///
    /// - Parameter option: an `Options` instance describing the change to be made to the request
    public func set(_ option: Options) {

        switch(option) {
        case .schema, .hostname, .port, .path, .username, .password:
            Log.error("Must use ClientRequest.init() to set URL components")
        case .method(let method):
            self.method = method
        case .headers(let headers):
            for (key, value) in headers {
                self.headers[key] = value
            }
        case .maxRedirects(let maxRedirects):
            self.maxRedirects = maxRedirects
        case .disableSSLVerification:
            self.disableSSLVerification = true
        }
    }

    /// Parse an URL String into options
    ///
    /// - Parameter urlString: URL of a String type
    ///
    /// - Returns: A `ClientRequest.Options` array
    public class func parse(_ urlString: String) -> [ClientRequest.Options] {

        if let url = URL(string: urlString) {
            return parse(url)
        }
        return []
    }

    /// Parse an URL class into options
    ///
    /// - Parameter url: Foundation URL class
    ///
    /// - Returns: A `ClientRequest.Options` array
    public class func parse(_ url: URL) -> [ClientRequest.Options] {

        var options: [ClientRequest.Options] = []

        if let scheme = url.scheme {
            options.append(.schema("\(scheme)://"))
        }
        if let host = url.host {
            options.append(.hostname(host))
        }
        var fullPath = url.path
        // query strings and parameters need to be appended here
        if let query = url.query {
            fullPath += "?"
            fullPath += query
        }
        options.append(.path(fullPath))
        if let port = url.port {
            options.append(.port(Int16(port)))
        }
        if let username = url.user {
            options.append(.username(username))
        }
        if let password = url.password {
            options.append(.password(password))
        }
        return options
    }

    /// Instance destruction
    deinit {

        if  let handle = handle  {
            curl_easy_cleanup(handle)
        }

        if  headersList != nil  {
            curl_slist_free_all(headersList)
        }

    }

    /// Add a string to the body of the request to be sent
    ///
    /// - Parameter from: The String to be added
    public func write(from string: String) {
        
        if  let data = string.data(using: .utf8)  {
            write(from: data)
        }
        
    }

    /// Add the bytes in a Data struct to the body of the request to be sent
    ///
    /// - Parameter from: The Data Struct containing the bytes to be added
    public func write(from data: Data) {
        
        writeBuffers.append(data: data)
        
    }

    /// Add a string to the body of the request to be sent and send the request
    /// to the remote server
    ///
    /// - Parameter from: The String to be added
    /// - Parameter close: If true, add the "Connection: close" header to the set
    ///                   of headers sent with the request
    public func end(_ data: String, close: Bool = false) {
        
        write(from: data)
        end(close: close)
        
    }

    /// Add the bytes in a Data struct to the body of the request to be sent
    /// and send the request to the remote server
    ///
    /// - Parameter from: The Data Struct containing the bytes to be added
    /// - Parameter close: If true, add the "Connection: close" header to the set
    ///                   of headers sent with the request
    public func end(_ data: Data, close: Bool = false) {
        
        write(from: data)
        end(close: close)
        
    }

    /// Send the request to the remote server
    ///
    /// - Parameter close: If true, add the "Connection: close" header to the set
    ///                   of headers sent with the request
    public func end(close: Bool = false) {

        closeConnection = close

        guard  let urlBuffer = url.cString(using: .utf8) else {
            callback(nil)
            return
        }
        
        prepareHandle(using: urlBuffer)

        let invoker = CurlInvoker(handle: handle!, maxRedirects: maxRedirects)
        invoker.delegate = self
        response = ClientResponse()
        
        var code = invoker.invoke()
        guard code == CURLE_OK else {
            Log.error("ClientRequest Error, Failed to invoke HTTP request. CURL Return code=\(code)")
            response!.release()
            callback(nil)
            return
        }
        
        code = curlHelperGetInfoLong(handle!, CURLINFO_RESPONSE_CODE, &response!.status)
        guard code == CURLE_OK else {
            Log.error("ClientRequest Error. Failed to get response code. CURL Return code=\(code)")
            response!.release()
            callback(nil)
            return
        }
        
        let parseStatus = response!.parse()
        guard parseStatus.error == nil else {
            Log.error("ClientRequest error. Failed to parse response. Error=\(parseStatus.error!)")
            response!.release()
            callback(nil)
            return
        }
        
        guard parseStatus.state == .headersComplete || parseStatus.state == .messageComplete else {
            Log.error("ClientRequest error. Failed to parse response. Status=\(parseStatus.state)")
            response!.release()
            callback(nil)
            return
        }
        
        self.callback(self.response)
    }

    /// Prepare the handle 
    ///
    /// Parameter using: The URL to use when preparing the handle
    private func prepareHandle(using urlBuffer: [CChar]) {
        
        handle = curl_easy_init()
        // HTTP parser does the decoding
        curlHelperSetOptInt(handle!, CURLOPT_HTTP_TRANSFER_DECODING, 0)
        curlHelperSetOptString(self.handle!, CURLOPT_URL, UnsafePointer(urlBuffer))
        if disableSSLVerification {
            curlHelperSetOptInt(handle!, CURLOPT_SSL_VERIFYHOST, 0)
            curlHelperSetOptInt(handle!, CURLOPT_SSL_VERIFYPEER, 0)
        }
        setMethod()
        let count = writeBuffers.count
        curlHelperSetOptInt(handle!, CURLOPT_POSTFIELDSIZE, count)
        setupHeaders()
        curlHelperSetOptString(handle!, CURLOPT_COOKIEFILE, "")

        // To see the messages sent by libCurl, uncomment the next line of code
        //curlHelperSetOptInt(handle, CURLOPT_VERBOSE, 1)
    }

    /// Sets the HTTP method in libCurl to the one specified in method
    private func setMethod() {

        let methodUpperCase = method.uppercased()
        switch(methodUpperCase) {
            case "GET":
                curlHelperSetOptBool(handle!, CURLOPT_HTTPGET, CURL_TRUE)
            case "POST":
                curlHelperSetOptBool(handle!, CURLOPT_POST, CURL_TRUE)
            case "PUT":
                curlHelperSetOptBool(handle!, CURLOPT_PUT, CURL_TRUE)
            case "HEAD":
                curlHelperSetOptBool(handle!, CURLOPT_NOBODY, CURL_TRUE)
            default:
                curlHelperSetOptString(handle!, CURLOPT_CUSTOMREQUEST, methodUpperCase)
        }

    }

    /// Sets the headers in libCurl to the ones in headers
    private func setupHeaders() {

        if closeConnection {
            headers["Connection"] = "close"
        }
        
        for (headerKey, headerValue) in headers {
            if let headerString = "\(headerKey): \(headerValue)".cString(using: .utf8) {
                headersList = curl_slist_append(headersList, UnsafePointer(headerString))
            }
        }
        curlHelperSetOptList(handle!, CURLOPT_HTTPHEADER, headersList)
    }

}

// MARK: CurlInvokerDelegate extension
extension ClientRequest: CurlInvokerDelegate {
    
    /// libCurl callback to recieve data sent by the server
    fileprivate func curlWriteCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int {
        
        response?.responseBuffers.append(bytes: UnsafeRawPointer(buf).assumingMemoryBound(to: UInt8.self), length: size)
        return size
        
    }

    /// libCurl callback to provide the data to send to the server
    fileprivate func curlReadCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int {
        
        let count = writeBuffers.fill(buffer: UnsafeMutableRawPointer(buf).assumingMemoryBound(to: UInt8.self), length: size)
        return count
        
    }

    /// libCurl callback invoked when a redirect is about to be done
    fileprivate func prepareForRedirect() {
        
        response?.responseBuffers.reset()
        writeBuffers.rewind()
        
    }
}

/// Helper class for invoking commands through libCurl
private class CurlInvoker {
    
    /// Pointer to the libCurl handle
    private var handle: UnsafeMutableRawPointer
    
    /// Delegate that can have a read or write callback
    fileprivate weak var delegate: CurlInvokerDelegate?
    
    /// Maximum number of redirects
    private let maxRedirects: Int

    /// Initializes a new CurlInvoker instance
    fileprivate init(handle: UnsafeMutableRawPointer, maxRedirects: Int) {
        
        self.handle = handle
        self.maxRedirects = maxRedirects
        
    }

    /// Run the HTTP method through the libCurl library
    ///
    /// - Returns: a status code for the success of the operation
    fileprivate func invoke() -> CURLcode {

        var rc: CURLcode = CURLE_FAILED_INIT
        if delegate == nil {
            return rc
        }

        withUnsafeMutablePointer(to: &delegate) {ptr in
            self.prepareHandle(ptr)

            var redirected = false
            var redirectCount = 0
            repeat {
                rc = curl_easy_perform(handle)

                if  rc == CURLE_OK  {
                    var redirectUrl: UnsafeMutablePointer<Int8>? = nil
                    let infoRc = curlHelperGetInfoCString(handle, CURLINFO_REDIRECT_URL, &redirectUrl)
                    if  infoRc == CURLE_OK {
                        if  redirectUrl != nil  {
                            curlHelperSetOptString(handle, CURLOPT_URL, redirectUrl)
                            redirected = true
                            delegate?.prepareForRedirect()
                            redirectCount+=1
                        }
                        else {
                            redirected = false
                        }
                    }
                }

            } while  rc == CURLE_OK  &&  redirected  &&  redirectCount < maxRedirects
        }

        return rc
    }

    /// Prepare the handle
    ///
    /// - Parameter ptr: pointer to the CurlInvokerDelegat
    private func prepareHandle(_ ptr: UnsafeMutablePointer<CurlInvokerDelegate?>) {

        curlHelperSetOptReadFunc(handle, ptr) { (buf: UnsafeMutablePointer<Int8>?, size: Int, nMemb: Int, privateData: UnsafeMutableRawPointer?) -> Int in

                let p = privateData?.assumingMemoryBound(to: CurlInvokerDelegate.self).pointee
                return (p?.curlReadCallback(buf!, size: size*nMemb))!
        }

        curlHelperSetOptWriteFunc(handle, ptr) { (buf: UnsafeMutablePointer<Int8>?, size: Int, nMemb: Int, privateData: UnsafeMutableRawPointer?) -> Int in

                let p = privateData?.assumingMemoryBound(to: CurlInvokerDelegate.self).pointee
                return (p?.curlWriteCallback(buf!, size: size*nMemb))!
        }
    }
    
}


/// Delegate protocol for objects operated by CurlInvoker
private protocol CurlInvokerDelegate: class {
    
    func curlWriteCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int
    func curlReadCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int
    func prepareForRedirect()
    
}


/// Singleton struct for one time initializations
private struct OneTimeInitializations {

    init() {
        curl_global_init(Int(CURL_GLOBAL_SSL))
    }
}

