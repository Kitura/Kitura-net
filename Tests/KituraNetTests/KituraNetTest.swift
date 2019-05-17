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

import XCTest

@testable import KituraNet

import Foundation
import Dispatch
import SSLService

struct KituraNetTestError: Swift.Error {
    let message: String
}

class KituraNetTest: XCTestCase {

    static let useSSLDefault = true
    static let portDefault = 8080
    static let portReuseDefault = false

    var useSSL = useSSLDefault
    var port = portDefault
    var unixDomainSocketPath: String? = nil

    static let sslConfig: SSLService.Configuration = {
        let sslConfigDir = URL(fileURLWithPath: #file).appendingPathComponent("../SSLConfig")

        #if os(Linux)
            let certificatePath = sslConfigDir.appendingPathComponent("certificate.pem").standardized.path
            let keyPath = sslConfigDir.appendingPathComponent("key.pem").standardized.path
            return SSLService.Configuration(withCACertificateDirectory: nil, usingCertificateFile: certificatePath,
                                            withKeyFile: keyPath, usingSelfSignedCerts: true, cipherSuite: nil)
        #else
            let chainFilePath = sslConfigDir.appendingPathComponent("certificateChain.pfx").standardized.path
            return SSLService.Configuration(withChainFilePath: chainFilePath, withPassword: "kitura",
                                            usingSelfSignedCerts: true, cipherSuite: nil)
        #endif
    }()
    
    static let clientSSLConfig = SSLService.Configuration(withCipherSuite: nil, clientAllowsSelfSignedCertificates: true)

    private static let initOnce: () = PrintLogger.use(colored: true)

    func doSetUp() {
        KituraNetTest.initOnce
    }

    func doTearDown() {
    }

    /// Start a server listening on a specified TCP port or Unix socket path.
    /// - Parameter delegate: The ServerDelegate that will handle requests to this server
    /// - Parameter port: The TCP port number to listen on
    /// - Parameter socketPath: The Unix socket path to listen on
    /// - Parameter useSSL: Whether to listen using SSL
    /// - Parameter allowPortReuse: Whether to allow the TCP port to be reused by other listeners
    /// - Returns: an HTTPServer instance.
    /// - Throws: an error if the server fails to listen on the specified port or path.
    func startServer(_ delegate: ServerDelegate?, port: Int = portDefault, unixDomainSocketPath: String? = nil, useSSL: Bool = useSSLDefault, allowPortReuse: Bool = portReuseDefault) throws -> HTTPServer {
        
        let server = HTTP.createServer()
        server.delegate = delegate
        server.allowPortReuse = allowPortReuse
        if useSSL {
            server.sslConfig = KituraNetTest.sslConfig
        }
        if let unixDomainSocketPath = unixDomainSocketPath {
            try server.listen(unixDomainSocketPath: unixDomainSocketPath)
        } else {
            try server.listen(on: port, address: "localhost")
        }
        return server
    }

    /// Convenience function for starting an HTTPServer on an ephemeral port,
    /// returning the a tuple containing the server and the port it is listening on.
    func startEphemeralServer(_ delegate: ServerDelegate?, useSSL: Bool = useSSLDefault, allowPortReuse: Bool = portReuseDefault) throws -> (server: HTTPServer, port: Int) {
        let server = try startServer(delegate, port: 0, useSSL: useSSL, allowPortReuse: allowPortReuse)
        guard let serverPort = server.port else {
            throw KituraNetTestError(message: "Server port was not initialized")
        }
        guard serverPort != 0 else {
            throw KituraNetTestError(message: "Ephemeral server port not set (was zero)")
        }
        return (server, serverPort)
    }
    
    func performServerTest(_ delegate: ServerDelegate?, port: Int = portDefault, useSSL: Bool = useSSLDefault, allowPortReuse: Bool = portReuseDefault,
                           line: Int = #line, asyncTasks: (XCTestExpectation) -> Void...) {

        do {
            self.useSSL = useSSL
            self.port = port

            let server: HTTPServer = try startServer(delegate, port: port, useSSL: useSSL, allowPortReuse: allowPortReuse)
            defer {
                server.stop()
            }

            let requestQueue = DispatchQueue(label: "Request queue")
            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(line: line, index: index)
                requestQueue.async() {
                    asyncTask(expectation)
                }
            }

            // wait for timeout or for all created expectations to be fulfilled
            waitExpectation(timeout: 10) { error in
                XCTAssertNil(error);
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    func performServerTest(_ delegate: ServerDelegate?, unixDomainSocketPath: String, useSSL: Bool = useSSLDefault,
                           line: Int = #line, asyncTasks: (XCTestExpectation) -> Void...) {

        do {
            self.useSSL = useSSL
            self.unixDomainSocketPath = unixDomainSocketPath

            let server: HTTPServer = try startServer(delegate, unixDomainSocketPath: unixDomainSocketPath, useSSL: useSSL)
            defer {
                server.stop()
            }

            let requestQueue = DispatchQueue(label: "Request queue")
            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(line: line, index: index)
                requestQueue.async() {
                    asyncTask(expectation)
                }
            }

            // wait for timeout or for all created expectations to be fulfilled
            waitExpectation(timeout: 10) { error in
                XCTAssertNil(error);
            }
        } catch {
            XCTFail("Error: \(error)")
        }
    }

    func performFastCGIServerTest(_ delegate: ServerDelegate?, port: Int = portDefault, allowPortReuse: Bool = portReuseDefault,
                                  line: Int = #line, asyncTasks: (XCTestExpectation) -> Void...) {

        do {
            self.port = port

            let server = try FastCGIServer.listen(on: port, address: "localhost", delegate: delegate)
            server.allowPortReuse = allowPortReuse
            defer {
                server.stop()
            }

            let requestQueue = DispatchQueue(label: "Request queue")
            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(line: line, index: index)
                requestQueue.async() {
                    asyncTask(expectation)
                }
            }

            // wait for timeout or for all created expectations to be fulfilled
            waitExpectation(timeout: 10) { error in
                XCTAssertNil(error);
            }
        }
        catch {
            XCTFail("Error: \(error)")
        }
    }

    func performRequest(_ method: String, path: String, unixDomainSocketPath: String? = nil, close: Bool=true, callback: @escaping ClientRequest.Callback,
                        headers: [String: String]? = nil, requestModifier: ((ClientRequest) -> Void)? = nil) {

        var allHeaders = [String: String]()
        if  let headers = headers  {
            for  (headerName, headerValue) in headers  {
                allHeaders[headerName] = headerValue
            }
        }
        allHeaders["Content-Type"] = "text/plain"

        let schema = self.useSSL ? "https" : "http"
        var options: [ClientRequest.Options] =
            [.method(method), .schema(schema), .hostname("localhost"), .port(Int16(self.port)), .path(path), .headers(allHeaders)]
        if self.useSSL {
            options.append(.disableSSLVerification)
        }

        let req = HTTP.request(options, unixDomainSocketPath: unixDomainSocketPath, callback: callback)
        if let requestModifier = requestModifier {
            requestModifier(req)
        }
        req.end(close: close)
    }

    func expectation(line: Int, index: Int) -> XCTestExpectation {
        return self.expectation(description: "\(type(of: self)):\(line)[\(index)]")
    }

    func waitExpectation(timeout: TimeInterval, handler: XCWaitCompletionHandler?) {
        self.waitForExpectations(timeout: timeout, handler: handler)
    }
}
