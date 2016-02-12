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

import sys
import BlueSocket

public class HttpServer {
    
    private static var listenerQueue = Queue(type: .PARALLEL, label: "HttpServer.listenerQueue")
    private static var clientHandlerQueue = Queue(type: .PARALLEL, label: "HttpServer.clientHAndlerQueue")

    
    public weak var delegate: HttpServerDelegate?
    
    private let spi: HttpServerSpi
    
    private var _port: Int?
    public var port: Int? {
        get { return _port }
    }
    
    private var listenSocket: BlueSocket?
    
    public init() {
        spi = HttpServerSpi()
        spi.delegate = self
    }

    public func listen(port: Int, notOnMainQueue: Bool=false) {
        self._port = port
		
		do {
			self.listenSocket = try BlueSocket.defaultConfigured()
		} catch let error as BlueSocketError {
			print("Error reported:\n \(error.description)")
		} catch {
            print("Unexpected error...")
		}

		let queuedBlock = {
			self.spi.spiListen(self.listenSocket, port: self._port!)
		}
		
		if  notOnMainQueue  {
			HttpServer.listenerQueue.queueAsync(queuedBlock)
		}
		else {
			Queue.queueIfFirstOnMain(HttpServer.listenerQueue, block: queuedBlock)
		}
    }

    public func stop() {
        if let listenSocket = listenSocket {
            spi.stopped = true
            listenSocket.close()
        }
    }

    public static func listen(port: Int, delegate: HttpServerDelegate, notOnMainQueue: Bool=false) -> HttpServer {
        let server = Http.createServer()
        server.delegate = delegate
        server.listen(port, notOnMainQueue: notOnMainQueue)
        return server
    }
}


extension HttpServer : HttpServerSpiDelegate {
    func handleClientRequest(clientSocket: BlueSocket) {
        if  let delegate = delegate  {
            HttpServer.clientHandlerQueue.queueAsync() {
                let response = ServerResponse(socket: clientSocket)
                let request = ServerRequest(socket: clientSocket)
                request.parse() { status in
                    switch status {
                    case .Success:
                        delegate.handleRequest(request, response: response)
                    case .ParsedLessThanRead:
                        print("ParsedLessThanRead")
                        response.statusCode = .BAD_REQUEST
                        do {
                            try response.end()
                        }
                        catch {
                            // handle error in connection
                        }
                    case .UnexpectedEOF:
                        print("UnexpectedEOF")
                    case .InternalError:
                        print("InternalError")
                    }
                }
            }
        }
    }
}


public protocol HttpServerDelegate: class {
    func handleRequest(request: ServerRequest, response: ServerResponse)
}
