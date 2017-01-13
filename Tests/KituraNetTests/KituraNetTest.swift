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

class KituraNetTest: XCTestCase {

    static let useSSLDefault = true
    static let portDefault = 8090

    var useSSL = useSSLDefault
    var port = portDefault

    static let sslConfig: SSLService.Configuration = {
        let path = #file
        let sslConfigDir: String
        if let range = path.range(of: "/", options: .backwards) {
            sslConfigDir = path.substring(to: range.lowerBound) + "/SSLConfig/"
        } else {
            sslConfigDir = "./SSLConfig/"
        }
        #if os(Linux)
            let certificatePath = sslConfigDir + "certificate.pem"
            let keyPath = sslConfigDir + "key.pem"
            return SSLService.Configuration(withCACertificateDirectory: nil, usingCertificateFile: certificatePath,
                                            withKeyFile: keyPath, usingSelfSignedCerts: true, cipherSuite: nil)
        #else
            let chainFilePath = sslConfigDir + "certificateChain.pfx"
            return SSLService.Configuration(withChainFilePath: chainFilePath, withPassword: "kitura",
                                            usingSelfSignedCerts: true, cipherSuite: nil)
        #endif
    }()

    func doSetUp() {
        PrintLogger.use()
    }

    func doTearDown() {
    }

    func performServerTest(_ delegate: ServerDelegate?, port: Int = portDefault, useSSL: Bool = useSSLDefault,
                           line: Int = #line, asyncTasks: @escaping (XCTestExpectation) -> Void...) {

        do {
            self.useSSL = useSSL
            self.port = port

            let server: HTTPServer
            if useSSL {
                server = try HTTPServer.listen(on: port, delegate: delegate, sslConfig: KituraNetTest.sslConfig)
            } else {
                server = try HTTPServer.listen(on: port, delegate: delegate)
            }
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

    func performFastCGIServerTest(_ delegate: ServerDelegate?, port: Int = portDefault,
                                  line: Int = #line, asyncTasks: @escaping (XCTestExpectation) -> Void...) {

        do {
            self.port = port

            let server = try FastCGIServer.listen(on: port, delegate: delegate)
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

    func performRequest(_ method: String, path: String, callback: @escaping ClientRequest.Callback,
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

        let req = HTTP.request(options, callback: callback)
        if let requestModifier = requestModifier {
            requestModifier(req)
        }
        req.end(close: true)
    }

    func expectation(line: Int, index: Int) -> XCTestExpectation {
        return self.expectation(description: "\(type(of: self)):\(line)[\(index)]")
    }

    func waitExpectation(timeout: TimeInterval, handler: XCWaitCompletionHandler?) {
        self.waitForExpectations(timeout: timeout, handler: handler)
    }
}
