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

// MARK: Socket type corresponds to /sys/bits/socket_type.h
enum SocketType {
    case STREAM, DGRAM
    
    func valueOf() -> Int32 {
        switch(self) {
            case .STREAM:
                return 1
	    case .DGRAM:
		return 2
        }
    }
}

enum SocketProtocol {
    case TCP
    
	// MARK: Perhaps should be handled differently on each platform
    func valueOf() -> Int32 {
        switch(self) {
            case .TCP:
                return Int32(IPPROTO_TCP)
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
            print("Error creating socket \(Socket.lastError()).")
            return nil
        }
    }
    
    
    func listen(port: Int16) -> Bool {
        var addr: sockaddr_in = sockaddr_in()
        memset(&addr, 0, sizeof(sockaddr_in))
        
        #if os(OSX)
        addr.sin_family = UInt8(AF_INET)
        #else
        addr.sin_family = UInt16(AF_INET)
        #endif

        addr.sin_port = UInt16(port).bigEndian

        // MARK: not sure if Linux needs this or not
        #if os(OSX)
            addr.sin_len = UInt8(sizeof(addr.dynamicType))
        #endif
        
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
                print("Error listening to port \(port). \(Socket.lastError()).")
                return false
            }
        }
        else {
            print("Error binding to port \(port). \(Socket.lastError()).")
            return false
        }
    }
    
    func accept() -> Socket? {
        var remoteAddr: sockaddr_in = sockaddr_in()
        var remoteAddrSize: socklen_t = 0
        
        var clientSocket: Int32
        
        repeat {
            #if os(Linux)
                clientSocket = Glibc.accept(fd, mutable_sockaddr_cast(&remoteAddr), &remoteAddrSize)
            #else
                clientSocket = Darwin.accept(fd, mutable_sockaddr_cast(&remoteAddr), &remoteAddrSize)
            #endif
        } while clientSocket == -1  &&  errno == EINTR
        
        if (-1 != clientSocket) {
            //let remoteAddrAscii = inet_ntoa(remoteAddr.sin_addr)
            //let remoteAddrStr = StringUtils.fromUtf8String(UnsafePointer<UInt8>(remoteAddrAscii))
            
            return Socket(fd: clientSocket)
        }
        else {
            print("Failed to accept a client on port \(port!). \(Socket.lastError()).")
            return nil
        }
    }
    
    
    private func sockaddr_cast(p: UnsafePointer<sockaddr_in>) -> UnsafePointer<sockaddr> {
        return UnsafePointer<sockaddr>(p)
    }
    
    
    private func mutable_sockaddr_cast(p: UnsafePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }
    
    private static func lastError() -> String {
         let str = String( strerror(errno)) 
         return str
        
    }
}
