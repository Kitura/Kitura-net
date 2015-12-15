//
//  Socket.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 9/8/15.
//  Copyright © 2015 IBM. All rights reserved.
//

#if os(OSX)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

import io
import sys

enum SocketProtocolFamily {
    case INET, INET6
    
    func valueOf() -> Int32 {
        switch(self) {
            case .INET:
                return AF_INET
            
            case .INET6:
                return AF_INET6
        }
    }
}

enum SocketType {
    case STREAM
    
    func valueOf() -> Int32 {
        switch(self) {
            case .STREAM:
                return SOCK_STREAM
        }
    }
}

enum SocketProtocol {
    case TCP
    
    func valueOf() -> Int32 {
        switch(self) {
            case .TCP:
                return IPPROTO_TCP
        }
    }
}


class Socket : FileDescriptor {
    
    var port: Int16?
    
    class func create(family: SocketProtocolFamily, type: SocketType, proto: SocketProtocol) -> Socket? {
        let sock = socket(family.valueOf(), type.valueOf(), proto.valueOf())
        if (-1 != sock) {
            return Socket(fd: sock)
        }
        else {
            print("Error creating socket \(StringUtils.fromUtf8String(strerror(errno)))")
            return nil
        }
    }
    
    
    func listen(port: Int16) -> Bool {
        var addr: sockaddr_in = sockaddr_in()
        memset(&addr, 0, sizeof(sockaddr_in))
        addr.sin_family = UInt8(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_len = UInt8(sizeof(addr.dynamicType))
        
        let addrSize: socklen_t = socklen_t(sizeof(addr.dynamicType))
        
        if (bind(fd, sockaddr_cast(&addr), addrSize) != -1) {
            #if os(Linux)
                let listenRc = Glibc.listen(fd, 5)
            #else
                let listenRc = Darwin.listen(fd, 5)
            #endif
            if (0 == listenRc) {
                self.port = port
                return true
            }
            else {
                print("Error listening to port \(port). \(StringUtils.fromUtf8String(strerror(errno)))")
                return false
            }
        }
        else {
            print("Error binding to port \(port). \(StringUtils.fromUtf8String(strerror(errno)))")
            return false
        }
    }
    
    func accept() -> Socket? {
        var remoteAddr: sockaddr_in = sockaddr_in()
        var remoteAddrSize: socklen_t = 0
        
        #if os(Linux)
            let clientSocket = Glibc.accept(fd, mutable_sockaddr_cast(&remoteAddr), &remoteAddrSize)
        #else
            let clientSocket = Darwin.accept(fd, mutable_sockaddr_cast(&remoteAddr), &remoteAddrSize)
        #endif
        if (-1 != clientSocket) {
            //let remoteAddrAscii = inet_ntoa(remoteAddr.sin_addr)
            //let remoteAddrStr = StringUtils.fromUtf8String(UnsafePointer<UInt8>(remoteAddrAscii))
            
            return Socket(fd: clientSocket)
        }
        else {
            print("Failed to accept a client on port \(port)")
            return nil
        }
    }
    
    
    private func sockaddr_cast(p: UnsafePointer<sockaddr_in>) -> UnsafePointer<sockaddr> {
        return UnsafePointer<sockaddr>(p)
    }
    
    
    private func mutable_sockaddr_cast(p: UnsafePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }
    
}