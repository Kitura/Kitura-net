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



#if os(Linux) || os(macOS)
import LoggerAPI
import Socket
import CCurl
import Foundation

// The public API for ClientRequest erroneously defines the port as an Int16, which is
// insufficient to hold all possible port values. To avoid a breaking change, we allow
// UInt16 bit patterns to be passed in, under the guises of an Int16, which we will
// then convert back to UInt16.
//
// User code must perform the equivalent conversion in order to pass in a value that
// is greater than Int16.max.
//
fileprivate extension Int16 {
    func toUInt16() -> UInt16 {
        return UInt16(bitPattern: self)
    }
}

// MARK: ClientRequest
/**
This class provides a set of low level APIs for issuing HTTP requests to another server. A new instance of the request can be created, along with options if the user would like to specify certain parameters such as HTTP headers, HTTP methods, host names, and SSL credentials. `Data` and `String` objects can be added to a `ClientRequest` too, and URLs can be parsed.

### Usage Example: ###
````swift
//Function to create a new `ClientRequest` using a URL.
 public static func request(_ url: String, callback: @escaping ClientRequest.Callback) -> ClientRequest {
     return ClientRequest(url: url, callback: callback)
 }

 //Create a new `ClientRequest` using a URL.
 let request = HTTP.request("http://localhost/8080") {response in
     ...
 }
````
*/
public class ClientRequest {

    /// Initialize the one time initialization struct to cause one time initializations to occur
    static private let oneTime = OneTimeInitializations()

    /**
     The set of HTTP headers to be sent with the request.
     
     ### Usage Example: ###
     ````swift
     clientRequest.headers["Content-Type"] = ["text/plain"]
     ````
     */
    public var headers = [String: String]()
    
    /**
     The URL for the request.
     
     ### Usage Example: ###
     ````swift
     clientRequest.url = "https://localhost:8080"
     ````
     */
    public private(set) var url: String = ""
    
    /**
     The HTTP method (i.e. GET, POST, PUT, DELETE) for the request.
     
     ### Usage Example: ###
     ````swift
     clientRequest.method = "post"
     ````
     */
    public private(set) var method: String = "get"
    
    /**
     The username to be used if using Basic Auth authentication.
     
     ### Usage Example: ###
     ````swift
     clientRequest.userName = "user1"
     ````
     */
    public private(set) var userName: String?
    
    /**
     The password to be used if using Basic Auth authentication.
     
     ### Usage Example: ###
     ````swift
     clientRequest.password = "sUpeR_seCurE_paSsw0rd"
     ````
     */
    public private(set) var password: String?

    /**
     The maximum number of redirects before failure.
     
     - Note: The `ClientRequest` class will automatically follow redirect responses. To avoid redirect loops, it will at maximum follow `maxRedirects` redirects.
     
     ### Usage Example: ###
     ````swift
     clientRequest.maxRedirects = 10
     ````
     */
    public private(set) var maxRedirects = 10
    
    /**
     If true, the "Connection: close" header will be added to the request that is sent.
     
     ### Usage Example: ###
     ````swift
     ClientRequest.closeConnection = false
     ````
     */
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

    /// Should HTTP/2 protocol be used
    private var useHTTP2 = false
    
    /// The Unix domain socket path used for the request
    private var unixDomainSocketPath: String? = nil


    /// Data that represents the "HTTP/2 " header status line prefix
    fileprivate static let Http2StatusLineVersion = "HTTP/2 ".data(using: .utf8)!

    /// Data that represents the "HTTP/2.0 " (with a minor) header status line prefix
    fileprivate static let Http2StatusLineVersionWithMinor = "HTTP/2.0 ".data(using: .utf8)!

    /// The hostname of the remote server
    private var hostName: String?

    /// The port number of the remote server
    private var port: Int?

    private var path = ""

    /**
    Client request options enum. This allows the client to specify certain parameteres such as HTTP headers, HTTP methods, host names, and SSL credentials.
    
    ### Usage Example: ###
    ````swift
    //If present in the options provided, the client will try to use HTTP/2 protocol for the connection.
    Options.useHTTP2
    ````
    */
    public enum Options {
        
        /// Specifies the HTTP method (i.e. PUT, POST...) to be sent in the request
        case method(String)
        
        /// Specifies the schema (i.e. HTTP, HTTPS) to be used in the URL of request
        case schema(String)
        
        /// Specifies the host name to be used in the URL of request
        case hostname(String)
        
        /// Specifies the port to be used in the URL of request.
        ///
        /// Note that an Int16 is incapable of representing all possible port values, however
        /// it forms part of the Kitura-net 2.0 API. In order to pass a port number greater
        /// than 32,767 (Int16.max), use the following code:
        /// ```
        /// let portNumber: UInt16 = 65535
        /// let portOption: ClientRequest.Options = .port(Int16(bitPattern: portNumber))
        /// ```
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
        
        /// If present, the client will try to use HTTP/2 protocol for the connection.
        case useHTTP2

    }

    /**
     Response callback closure type.
     
     ### Usage Example: ###
     ````swift
     var ClientRequest.headers["Content-Type"] = ["text/plain"]
     ````
     
     - Parameter ClientResponse: The `ClientResponse` object that describes the response that was received from the remote server.
     
     */
    public typealias Callback = (ClientResponse?) -> Void

    /// Initializes a `ClientRequest` instance
    ///
    /// - Parameter url: url for the request 
    /// - Parameter callback: The closure of type `Callback` to be used for the callback.
    init(url: String, callback: @escaping Callback) {
        
        self.url = url
        self.callback = callback
        if let url = URL(string: url) {
            removeHttpCredentialsFromUrl(url)
        }
    }

    private func removeHttpCredentialsFromUrl(_ url: URL) {
        if let host = url.host {
            self.hostName = host
        }

        if let port = url.port {
            self.port = port
        }

        if let username = url.user {
            self.userName = username
        }

        if let password = url.password {
            self.password = password
        }

        var fullPath = url.path

        // query strings and parameters need to be appended here
        if let query = url.query {
            fullPath += "?"
            fullPath += query
        }

        self.path = fullPath
        self.url = "\(url.scheme ?? "http")://\(self.hostName ?? "unknown")\(self.port.map { ":\($0)" } ?? "")\(fullPath)"
        if let username = self.userName, let password = self.password {
            self.headers["Authorization"] = createHTTPBasicAuthHeader(username: username, password: password)
        }
        return
    }

    /// Initializes a `ClientRequest` instance
    ///
    /// - Parameter options: An array of `Options' describing the request.
    /// - Parameter unixDomainSocketPath: Specifies the path of a Unix domain socket that the client should connect to.
    /// - Parameter callback: The closure of type `Callback` to be used for the callback.
    init(options: [Options], unixDomainSocketPath: String? = nil, callback: @escaping Callback) {

        self.unixDomainSocketPath = unixDomainSocketPath
        self.callback = callback

        var theSchema = "http://"
        var hostName = "localhost"
        var path = ""
        var port = ""

        for option in options  {
            switch(option) {

                case .method, .headers, .maxRedirects, .disableSSLVerification, .useHTTP2:
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
                    let portNumber = thePort.toUInt16()
                    port = ":\(portNumber)"
                case .path(var thePath):
                    if thePath.first != "/" {
                      thePath = "/" + thePath
                    }
                    path = thePath
                case .username(let userName):
                    self.userName = userName
                case .password(let password):
                    self.password = password
            }
        }

        if let username = self.userName, let password = self.password {
            self.headers["Authorization"] = createHTTPBasicAuthHeader(username: username, password: password)
        }
        url = "\(theSchema)\(hostName)\(port)\(path)"

    }

    /**
     Set a single option in the request. URL parameters must be set in init().
     
     ### Usage Example: ###
     ````swift
     var options: [ClientRequest.Options] = []
     options.append(.port(Int16(port)))
     clientRequest.set(options)
     ````
     
     - Parameter option: An `Options` instance describing the change to be made to the request.
     
     */
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
        case .useHTTP2:
            self.useHTTP2 = true
        }
    }


    /**
     Parse an URL (String) into an array of ClientRequest.Options.
     
     ### Usage Example: ###
     ````swift
     let url: String = "http://www.website.com"
     let parsedOptions = clientRequest.parse(url)
     ````
     
     - Parameter urlString: A String object referencing a URL.
     - Returns: An array of `ClientRequest.Options`
     */
    public class func parse(_ urlString: String) -> [ClientRequest.Options] {

        if let url = URL(string: urlString) {
            return parse(url)
        }
        return []
    }

    /**
     Parse an URL Foudation object into an array of ClientRequest.Options.
     
     ### Usage Example: ###
     ````swift
     let url: URL = URL(string: "http://www.website.com")!
     let parsedOptions = clientRequest.parse(url)
     ````
     
     - Parameter url: Foundation URL object.
     - Returns: An array of `ClientRequest.Options`
    */
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
            options.append(.port(Int16(bitPattern: UInt16(port))))
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

    /**
     Add a String to the body of the request to be sent.
     
     ### Usage Example: ###
     ````swift
     let stringToSend: String = "send something"
     clientRequest.write(from: stringToSend)
     ````
     
     - Parameter from: The String to be added to the request.
     */
    public func write(from string: String) {
        
        if  let data = string.data(using: .utf8)  {
            write(from: data)
        }
        
    }

    /**
     Add the bytes in a Data struct to the body of the request to be sent.
     
     ### Usage Example: ###
     ````swift
     let string = "some some more stuff"
     if let data: Data = string.data(using: .utf8) {
        clientRequest.write(from: data)
     }
     
     ````
     
     - Parameter from: The Data Struct containing the bytes to be added to the request.
     */
    public func write(from data: Data) {
        
        writeBuffers.append(data: data)
        
    }

    /**
     Add a String to the body of the request to be sent and then send the request to the remote server.
     
     ### Usage Example: ###
     ````swift
     let data: String = "send something"
     clientRequest.end(from: data, close: true)
     ````
     
     - Parameter data: The String to be added to the request.
     - Parameter close: If true, add the "Connection: close" header to the set of headers sent with the request.
     */
    public func end(_ data: String, close: Bool = false) {
        
        write(from: data)
        end(close: close)
        
    }

    /**
     Add the bytes in a Data struct to the body of the request to be sent and then send the request to the remote server.
     
     ### Usage Example: ###
     ````swift
     let stringToSend = "send this"
     let data: Data = stringToSend.data(using: .utf8) {
        clientRequest.end(from: data, close: true)
     }
     ````
     
     - Parameter data: The Data struct containing the bytes to be added to the request.
     - Parameter close: If true, add the "Connection: close" header to the set of headers sent with the request.
     */
    public func end(_ data: Data, close: Bool = false) {
        
        write(from: data)
        end(close: close)
        
    }

    /**
     Send the request to the remote server.
     
     ### Usage Example: ###
     ````swift
     clientRequest.end(true)
     ````
     
     - Parameter close: If true, add the "Connection: close" header to the set of headers sent with the request.
     */
    public func end(close: Bool = false) {

        closeConnection = close

        guard  let urlBuffer = url.cString(using: .utf8) else {
            callback(nil)
            return
        }
        
        prepareHandle(using: urlBuffer)

        let invoker = CurlInvoker(handle: handle!, maxRedirects: maxRedirects)
        invoker.delegate = self
        let skipBody = (method.uppercased() == "HEAD")
        response = ClientResponse(skipBody: skipBody)
        
        var code = invoker.invoke()
        guard code == CURLE_OK else {
            Log.error("ClientRequest Error, Failed to invoke HTTP request. CURL Return code=\(code)")
            callback(nil)
            return
        }
        
        code = curlHelperGetInfoLong(handle!, CURLINFO_RESPONSE_CODE, &response!.status)
        guard code == CURLE_OK else {
            Log.error("ClientRequest Error. Failed to get response code. CURL Return code=\(code)")
            callback(nil)
            return
        }
        
        var httpStatusCode = response!.httpStatusCode
        
        repeat {
            let parseStatus = response!.parse()
            guard parseStatus.error == nil else {
                Log.error("ClientRequest error. Failed to parse response. Error=\(parseStatus.error!)")
                callback(nil)
                return
            }
        
            guard parseStatus.state == .messageComplete else {
                Log.error("ClientRequest error. Failed to parse response. Status=\(parseStatus.state)")
                callback(nil)
                return
            }
            
            httpStatusCode = response!.httpStatusCode
        } while httpStatusCode == .continue || httpStatusCode == .switchingProtocols
        
        self.callback(self.response)
    }

    /// Prepare the handle 
    ///
    /// Parameter using: The URL to use when preparing the handle
    private func prepareHandle(using urlBuffer: [CChar]) {
        
        handle = curl_easy_init()
        // HTTP parser does the decoding
        curlHelperSetOptInt(handle!, CURLOPT_HTTP_TRANSFER_DECODING, 0)
        urlBuffer.withUnsafeBufferPointer { bufferPointer in
            _ = curlHelperSetOptString(self.handle!, CURLOPT_URL, bufferPointer.baseAddress!)
        }
        if disableSSLVerification {
            curlHelperSetOptInt(handle!, CURLOPT_SSL_VERIFYHOST, 0)
            curlHelperSetOptInt(handle!, CURLOPT_SSL_VERIFYPEER, 0)
        }
        setMethodAndContentLength()
        setupHeaders()
        curlHelperSetOptString(handle!, CURLOPT_COOKIEFILE, "")

        // To see the messages sent by libCurl, uncomment the next line of code
        //curlHelperSetOptInt(handle, CURLOPT_VERBOSE, 1)
		
        if useHTTP2 {
            curlHelperSetOptInt(handle!, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0)
        }
        
        if let socketPath = unixDomainSocketPath?.cString(using: .utf8) {
            socketPath.withUnsafeBufferPointer { bufferPointer in
                _ = curlHelperSetUnixSocketPath(handle!, bufferPointer.baseAddress!)
            }
        }
    }

    /// Sets the HTTP method and Content-Length in libCurl
    private func setMethodAndContentLength() {

        let methodUpperCase = method.uppercased()
        let count = writeBuffers.count
        switch(methodUpperCase) {
            case "GET":
                curlHelperSetOptBool(handle!, CURLOPT_HTTPGET, CURL_TRUE)
            case "POST":
                curlHelperSetOptBool(handle!, CURLOPT_POST, CURL_TRUE)
                curlHelperSetOptInt(handle!, CURLOPT_POSTFIELDSIZE, count)
            case "PUT":
                curlHelperSetOptBool(handle!, CURLOPT_UPLOAD, CURL_TRUE)
                curlHelperSetOptInt(handle!, CURLOPT_INFILESIZE, count)
            case "HEAD":
                curlHelperSetOptBool(handle!, CURLOPT_NOBODY, CURL_TRUE)
            case "PATCH":
                curlHelperSetOptString(handle!, CURLOPT_CUSTOMREQUEST, methodUpperCase)
                curlHelperSetOptBool(handle!, CURLOPT_UPLOAD, CURL_TRUE)
                curlHelperSetOptInt(handle!, CURLOPT_INFILESIZE, count)
            default:
                curlHelperSetOptString(handle!, CURLOPT_CUSTOMREQUEST, methodUpperCase)
        }

    }

    /// Sets the headers in libCurl to the ones in headers
    private func setupHeaders() {

        if closeConnection {
            headers["Connection"] = "close"
        }
        // Unless the user has provided an Expect header, set an empty one to disable
        // curl's default Expect: 100-continue behaviour, since Kitura does not support it.
        if !headers.keys.contains("Expect") {
            headers["Expect"] = ""
        }
        for (headerKey, headerValue) in headers {
            if let headerString = "\(headerKey): \(headerValue)".cString(using: .utf8) {
                
                headerString.withUnsafeBufferPointer { bufferPointer in
                    
                    headersList = curl_slist_append(headersList, bufferPointer.baseAddress!)
                }
            }
        }
        curlHelperSetOptList(handle!, CURLOPT_HTTPHEADER, headersList)
    }

    private func createHTTPBasicAuthHeader(username: String, password: String) -> String {
        let authHeader = "\(username):\(password)"
        let data = Data(authHeader.utf8)
        return "Basic \(data.base64EncodedString())"
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
    
    /// libCurl callback to recieve header sent by the server. Being called per each header line.
    fileprivate func curlHeaderCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int {
        // If the header status line begins with 'HTTP/2 ' we replace it with 'HTTP/2.0' because
        // otherwise the CHTTPParser will parse this line incorrectly and won't extract the status code
#if swift(>=5.0)
        ClientRequest.Http2StatusLineVersion.withUnsafeBytes() { (rawPtr: UnsafeRawBufferPointer) -> Void in
            if memcmp(rawPtr.baseAddress!, buf, ClientRequest.Http2StatusLineVersion.count) == 0 {
                ClientRequest.Http2StatusLineVersionWithMinor.withUnsafeBytes() { (p: UnsafeRawBufferPointer) -> Void in
                    response?.responseBuffers.append(bytes: p.bindMemory(to: UInt8.self).baseAddress!, length: ClientRequest.Http2StatusLineVersionWithMinor.count)
                    response?.responseBuffers.append(bytes: UnsafeRawPointer(buf).assumingMemoryBound(to: UInt8.self) + ClientRequest.Http2StatusLineVersion.count,
                                                     length: size - ClientRequest.Http2StatusLineVersion.count)
                }
            }
            else {
                response?.responseBuffers.append(bytes: UnsafeRawPointer(buf).assumingMemoryBound(to: UInt8.self), length: size)
            }
        }
#else
        ClientRequest.Http2StatusLineVersion.withUnsafeBytes() { (ptr: UnsafePointer<UInt8>) -> Void in
            if memcmp(ptr, buf, ClientRequest.Http2StatusLineVersion.count) == 0 {
                ClientRequest.Http2StatusLineVersionWithMinor.withUnsafeBytes() { (p: UnsafePointer<UInt8>) -> Void in
                    response?.responseBuffers.append(bytes: p, length: ClientRequest.Http2StatusLineVersionWithMinor.count)
                    response?.responseBuffers.append(bytes: UnsafeRawPointer(buf).assumingMemoryBound(to: UInt8.self) + ClientRequest.Http2StatusLineVersion.count,
                                                     length: size - ClientRequest.Http2StatusLineVersion.count)
                }
            }
            else {
                response?.responseBuffers.append(bytes: UnsafeRawPointer(buf).assumingMemoryBound(to: UInt8.self), length: size)
            }
        }
#endif
        
        return size
        
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
        guard let delegate = self.delegate else {
            return rc
        }

        withUnsafeMutablePointer(to: &self.delegate) {ptr in
            self.prepareHandle(ptr)

            var redirected = false
            var redirectCount = 0
            repeat {
                rc = curl_easy_perform(handle)

                if  rc == CURLE_OK  {
                    var redirectUrl: UnsafeMutablePointer<Int8>? = nil
                    let infoRc = curlHelperGetInfoCString(handle, CURLINFO_REDIRECT_URL, &redirectUrl)
                    if  infoRc == CURLE_OK {
                        if  redirectUrl != nil {
                            redirectCount += 1
                            if redirectCount <= maxRedirects {
                                // Prepare to do a redirect
                                curlHelperSetOptString(handle, CURLOPT_URL, redirectUrl)
                                var status: Int = -1
                                let codeRc = curlHelperGetInfoLong(handle, CURLINFO_RESPONSE_CODE, &status)
                                // If the status code was 303 See Other, ensure that
                                // the redirect is done with a GET query rather than
                                // whatever might have just been used.
                                if codeRc == CURLE_OK && status == 303 {
                                    _ = curlHelperSetOptInt(handle, CURLOPT_HTTPGET, 1)
                                }
                                redirected = true
                                delegate.prepareForRedirect()
                            }
                            else {
                                redirected = false
                            }
                        }
                        else {
                            redirected = false
                        }
                    }
                }

            } while  rc == CURLE_OK  &&  redirected
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
        
        curlHelperSetOptHeaderFunc(handle, ptr) { (buf: UnsafeMutablePointer<Int8>?, size: Int, nMemb: Int, privateData: UnsafeMutableRawPointer?) -> Int in
            
                let p = privateData?.assumingMemoryBound(to: CurlInvokerDelegate.self).pointee
                return (p?.curlHeaderCallback(buf!, size: size*nMemb))!
        }
    }
    
}


/// Delegate protocol for objects operated by CurlInvoker
private protocol CurlInvokerDelegate: AnyObject {
    
    func curlWriteCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int
    func curlReadCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int
    func curlHeaderCallback(_ buf: UnsafeMutablePointer<Int8>, size: Int) -> Int
    func prepareForRedirect()
    
}


/// Singleton struct for one time initializations
private struct OneTimeInitializations {

    init() {
        curl_global_init(Int(CURL_GLOBAL_SSL))
    }
}

#endif
