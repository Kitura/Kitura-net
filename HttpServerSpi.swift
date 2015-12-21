//
//  HttpServerSpi.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 9/7/15.
//  Copyright © 2015 IBM. All rights reserved.
//

class HttpServerSpi {
    
    weak var delegate: HttpServerSpiDelegate?

    func spiListen(socket: Socket?, port: Int) {
        
        if  let s = socket, let d = delegate {
            if  s.listen(Int16(port))  {
            
                print("Listening on port \(port)")
                
                while  let clientSocket = s.accept() {
                    d.handleClientRequest(clientSocket)
                }
            }
        }
    }
}

protocol HttpServerSpiDelegate: class {
    func handleClientRequest(socket: Socket)
}
