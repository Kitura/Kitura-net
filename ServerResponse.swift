//
//  ServerResponse.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 10/20/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import ETSocket

import Foundation

public class ServerResponse : ETWriter {
    private var socket: ETSocket?
    
    private var startFlushed = false
    
    private var singleHeaders: [String: String] = [:]
    private var multiHeaders: [String: [String]] = [:]
    
    public var status = HttpStatusCode.OK.rawValue
    public var statusCode: HttpStatusCode? {
        get {
            return HttpStatusCode(rawValue: status)
        }
        set (newValue) {
            if  !startFlushed  &&  newValue != nil {
                status = newValue!.rawValue
            }
        }
    }
    
    init(socket: ETSocket) {
        self.socket = socket
        setHeader("Date", value: SpiUtils.httpDate())
    }
    
    public func getHeader(key: String) -> String? {
        return singleHeaders[key]
    }
    
    public func getHeaders(key: String) -> [String]? {
        return multiHeaders[key]
    }
    
    public func setHeader(key: String, value: String) {
        singleHeaders[key] = value
        multiHeaders.removeValueForKey(key)
    }
    
    public func setHeader(key: String, value: [String]) {
        multiHeaders[key] = value
        singleHeaders.removeValueForKey(key)
    }
    
    public func removeHeader(key: String) {
        singleHeaders.removeValueForKey(key)
        multiHeaders.removeValueForKey(key)
    }
    
    public func writeString(text: String) throws {
        if  let s = socket {
            try flushStart()
            try s.writeString(text)
        }
    }
    
    public func writeData(data: NSData) throws {
        if  let s = socket {
            try flushStart()
            try s.writeData(data)
        }
    }
    
    public func end(text: String) throws {
        try writeString(text)
        try end()
    }
    
    public func end() throws {
        if  let s = socket {
            try flushStart()
            s.close()
            socket = nil
        }
    }
    
    private func flushStart() throws {
        if  !startFlushed  {
            
            try socket!.writeString("HTTP/1.1 ")
            try socket!.writeString(String(status))
            try socket!.writeString(" ")
            var statusText = Http.statusCodes[status]
            if  statusText == nil {
                statusText = ""
            }
            try socket!.writeString(statusText!)
            try socket!.writeString("\r\n")
            
            for (key, value) in singleHeaders {
                try socket!.writeString(key)
                try socket!.writeString(": ")
                try socket!.writeString(value)
                try socket!.writeString("\r\n")
            }
            for (key, valueSet) in multiHeaders {
                for value in valueSet {
                    try socket!.writeString(key)
                    try socket!.writeString(": ")
                    try socket!.writeString(value)
                    try socket!.writeString("\r\n")
                }
            }
            
            try socket!.writeString("\r\n")
            
            startFlushed = true
        }
    }
}
