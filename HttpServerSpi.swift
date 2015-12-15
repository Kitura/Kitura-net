//
//  HttpServerSpi.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 9/7/15.
//  Copyright © 2015 IBM. All rights reserved.
//

#if os(OSX)
    import Darwin
#else
    import Glibc
#endif

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
    
    private func sockaddr_cast(p: UnsafePointer<sockaddr_in>) -> UnsafePointer<sockaddr> {
        return UnsafePointer<sockaddr>(p)
    }
    
    private func mutable_sockaddr_cast(p: UnsafePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }
}

protocol HttpServerSpiDelegate: class {
    func handleClientRequest(socket: Socket)
}
