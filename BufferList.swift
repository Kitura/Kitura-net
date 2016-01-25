//
//  BufferList.swift
//  Pods
//
//  Created by Samuel Kallner on 11/23/15.
//
//

#if os(OSX)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

import Foundation

public class BufferList {
    private var lclData = NSMutableData(capacity: 4096)
    private var byteIndex = 0
    
    public var count: Int {
        return lclData!.length
    }
    
    public var data: NSData? {
        return lclData as NSData?
    }
    
    public init() {}
    
    public func appendBytes(bytes: UnsafePointer<UInt8>, length: Int) {
        lclData!.appendBytes(bytes, length: length)
    }
    
    public func appendData(data: NSData) {
        lclData!.appendBytes(data.bytes, length: data.length)
    }
    
    public func fillArray(inout buffer: [UInt8]) -> Int {
        let result = min(buffer.count, lclData!.length-byteIndex)
        memcpy(UnsafeMutablePointer<UInt8>(buffer), lclData!.bytes+byteIndex, result)
        byteIndex += result
        
        return result
    }
    
    public func fillBuffer(buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Int {
        let result = min(length, lclData!.length-byteIndex)
        memcpy(buffer, lclData!.bytes+byteIndex, result)
        byteIndex += result
        
        return result
    }
    
    public func fillData(data: NSMutableData) -> Int {
        let result = lclData!.length-byteIndex
        data.appendBytes(lclData!.bytes+byteIndex, length: result)
        byteIndex += result
        return result
    }
    
    public func reset() {
        lclData!.length = 0
        byteIndex = 0
    }
    
    public func rewind() {
        byteIndex = 0
    }
    
}
