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

protocol KituraNetTest {

    func expectation(line: Int, index: Int) -> XCTestExpectation
    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?)
}

extension KituraNetTest {

    func doSetUp() {
        PrintLogger.use()
    }

    func doTearDown() {
        //       sleep(10)
    }
    
    func performServerTest(_ delegate: ServerDelegate?, useSSL: Bool = true, line: Int = #line,
                           asyncTasks: @escaping (XCTestExpectation) -> Void...) {
        var expectations: [XCTestExpectation] = []
        
        for index in 0..<asyncTasks.count {
            expectations.append(expectation(line: line, index: index))
        }
        
        // convert var to let to get around compile error on 3.0 Release in Xcode 8.1
        let exps = expectations
        
        let requestQueue = DispatchQueue(label: "Request queue")

        var server: HTTPServer?

        do {
            if useSSL {
                server = try HTTPServer.listen(on: 8090, delegate: delegate, sslConfig: TestSSLConfig.sslConfig)
            } else {
                server = try HTTPServer.listen(on: 8090, delegate: delegate)
            }

            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = exps[index]
                requestQueue.async {
                    asyncTask(expectation)
                }
            }

            waitExpectation(timeout: 10) { error in
                // blocks test until request completes
                server?.stop()
                XCTAssertNil(error);
            }
        } catch let error {
            XCTFail("Error: \(error)")
            server?.stop()
        }
    }
    
    func performFastCGIServerTest(_ delegate: ServerDelegate?, line: Int = #line, asyncTasks: @escaping (XCTestExpectation) -> Void...) {
        var expectations: [XCTestExpectation] = []
        
        for index in 0..<asyncTasks.count {
            expectations.append(expectation(line: line, index: index))
        }
        
        // convert var to let to get around compile error on 3.0 Release in Xcode 8.1
        let exps = expectations
        
        let requestQueue = DispatchQueue(label: "Request queue")
        
        var server: FastCGIServer?
        do {
            server = try FastCGIServer.listen(on: 9000, delegate: delegate)

            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = exps[index]
                requestQueue.async {
                    asyncTask(expectation)
                }
            }
            
            waitExpectation(timeout: 10) { error in
                // blocks test until request completes
                server?.stop()
                XCTAssertNil(error);
            }
        }
        catch {
            XCTFail("Failed to create a FastCGI server. Error=\(error)")
            server?.stop()
        }
    }

    func performRequest(_ method: String, path: String, useSSL: Bool = true, callback: @escaping ClientRequest.Callback,
                        headers: [String: String]? = nil, requestModifier: ((ClientRequest) -> Void)? = nil) {
        var allHeaders = [String: String]()
        if  let headers = headers  {
            for  (headerName, headerValue) in headers  {
                allHeaders[headerName] = headerValue
            }
        }
        allHeaders["Content-Type"] = "text/plain"
        let schema = useSSL ? "https" : "http"
        var options: [ClientRequest.Options] =
            [.method(method), .schema(schema), .hostname("localhost"), .port(8090), .path(path), .headers(allHeaders)]
        if useSSL {
            options.append(.disableSSLVerification)
        }
        let req = HTTP.request(options, callback: callback)
        if let requestModifier = requestModifier {
            requestModifier(req)
        }
        req.end(close: true)
    }
}

extension XCTestCase: KituraNetTest {

    func expectation(line: Int, index: Int) -> XCTestExpectation {
        return self.expectation(description: "\(type(of: self)):\(line)[\(index)]")
    }

    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?) {
        self.waitForExpectations(timeout: t, handler: handler)
    }
}

class TestSSLConfig {
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
}
