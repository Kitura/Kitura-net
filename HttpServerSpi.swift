//
//  HttpServerSpi.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 9/7/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import ETSocket
import Logger

class HttpServerSpi {
    
    weak var delegate: HttpServerSpiDelegate?

    func spiListen(socket: ETSocket?, port: Int) {
		do {
			if  let socket = socket, let delegate = delegate {
				try socket.listenOn(port)
				Logger.info("Listening on port \(port)")
				
				// TODO: Figure out a way to shutdown the server...
				repeat {
					let clientSocket = try socket.acceptConnectionAndKeepListening()
					Logger.info("Accepted connection from: \(clientSocket.remoteHostName) on port \(clientSocket.remotePort)")
					
					delegate.handleClientRequest(clientSocket)
				} while true
			}
		} catch let error as ETSocketError {
			Logger.error("Error reported:\n \(error.description)")
		} catch {
			Logger.error("Unexpected error...")
		}
    }
}

protocol HttpServerSpiDelegate: class {
	func handleClientRequest(socket: ETSocket)
}
