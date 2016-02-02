//
//  HttpServerSpi.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 9/7/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import ETSocket
import HeliumLogger

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
