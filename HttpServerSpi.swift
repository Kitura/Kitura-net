//
//  HttpServerSpi.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 9/7/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import ETSocket

class HttpServerSpi {
    
    weak var delegate: HttpServerSpiDelegate?

    func spiListen(socket: ETSocket?, port: Int) {
		
		do {
			
			if  let s = socket, let d = delegate {
				
				try s.listenOn(port)
				
				print("Listening on port \(port)")
				
				// TODO: Figure out a way to shutdown the server...
				repeat {
				
					let clientSocket = try s.acceptConnectionAndKeepListening()
				
					print("Accepted connection from: \(clientSocket.remoteHostName) on port \(clientSocket.remotePort)")
					
					d.handleClientRequest(clientSocket)
				
				} while true
			}
			
		} catch let error as ETSocketError {
			
			print("Error reported:\n \(error.description)")
			
		} catch {
			
			print("Unexpected error...")
		}
    }
}

protocol HttpServerSpiDelegate: class {
	func handleClientRequest(socket: ETSocket)
}
