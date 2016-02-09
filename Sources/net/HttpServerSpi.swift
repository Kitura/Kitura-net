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

import BlueSocket
import LoggerAPI

class HttpServerSpi {
    
    weak var delegate: HttpServerSpiDelegate?

    func spiListen(socket: ETSocket?, port: Int) {
		do {
			if  let socket = socket, let delegate = delegate {
				try socket.listenOn(port)
				Log.info("Listening on port \(port)")
				
				// TODO: Change server exit to not rely on error being thrown
				repeat {
					let clientSocket = try socket.acceptConnectionAndKeepListening()
					Log.info("Accepted connection from: \(clientSocket.remoteHostName) on port \(clientSocket.remotePort)")
					
					delegate.handleClientRequest(clientSocket)
				} while true
			}
		} catch let error as ETSocketError {
			Log.error("Error reported:\n \(error.description)")
		} catch {
			Log.error("Unexpected error...")
		}
    }
}

protocol HttpServerSpiDelegate: class {
	func handleClientRequest(socket: ETSocket)
}
