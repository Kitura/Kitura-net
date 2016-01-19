//
//  IncomingMessage.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 10/20/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import io
import sys
import ETSocket

import Foundation

public class IncomingMessage : HttpParserDelegate, ETReader {
    
    private static let BUFFER_SIZE = 2000
    
    public var httpVersionMajor: UInt16?
    
    public var httpVersionMinor: UInt16?
    
    public var headers = [String:String]()
    
    public var rawHeaders = [String]()
    
    public var method: String = "" // TODO: enum?
    
    public var urlString = ""
    
    public var url = NSMutableData()
        
    // TODO: trailers
    
    private var lastHeaderWasAValue = false
    
    private var lastHeaderField = NSMutableData()
    
    private var lastHeaderValue = NSMutableData()
    
    private var httpParser: HttpParser?
    
    private var status = Status.Initial
    
    private var bodyChunk = BufferList()
    
    private var helper: IncomingMessageHelper?
    
    private var ioBuffer = NSMutableData(capacity: BUFFER_SIZE)
    private var buffer = NSMutableData(capacity: BUFFER_SIZE)
    
    
    private enum Status {
        case Initial
        case HeadersComplete
        case MessageComplete
        case Error
    }
    
    
    public enum HttpParserErrorType {
        case Success
        case ParsedLessThanRead
        case UnexpectedEOF
        case InternalError // TODO
    }
    
    
    init (isRequest: Bool) {
        httpParser = HttpParser(isRequest: isRequest)
        httpParser!.delegate = self
    }
    
    func setup(helper: IncomingMessageHelper) {
        self.helper = helper
    }
    
    
    func parse (callback: (HttpParserErrorType) -> Void) {
        if let parser = httpParser where status == .Initial {
            while status == .Initial {
                do {
                    ioBuffer!.length = 0
                    let length = try helper!.readDataHelper(ioBuffer!)
                    if length > 0 {
                        let (nparsed, upgrade) = parser.execute(UnsafePointer<Int8>(ioBuffer!.bytes), length: length)
                        if upgrade == 1 {
                            // TODO handle new protocol
                        }
                        else if (nparsed != length) {
                            /* Handle error. Usually just close the connection. */
                            freeHttpParser()
                            callback(.ParsedLessThanRead)
                        }
                    }
                }
                catch {
                    /* Handle error. Usually just close the connection. */
                    freeHttpParser()
                    callback(.UnexpectedEOF)
                }
            }
            
            callback(.Success)
        }
        else {
            freeHttpParser()
            callback(.InternalError)
        }
    }
    
    
    public func readData(data: NSMutableData) throws -> Int {
        var count = bodyChunk.fillData(data)
        if count == 0 {
            if let parser = httpParser where status == .HeadersComplete {
                do {
                    ioBuffer!.length = 0
                    count = try helper!.readDataHelper(ioBuffer!)
                    if count > 0 {
                        let (nparsed, upgrade) = parser.execute(UnsafePointer<Int8>(ioBuffer!.bytes), length: count)
                        if upgrade == 1 {
                            // TODO: handle new protocol
                        }
                        else if (nparsed != count) {
                            /* Handle error. Usually just close the connection. */
                            freeHttpParser()
                            status = .Error
                        }
                        else {
                            count = bodyChunk.fillData(data)
                        }
                    }
                    else {
                        status = .MessageComplete
                        freeHttpParser()
                    }
                }
                catch let error {
                    /* Handle error. Usually just close the connection. */
                    freeHttpParser()
                    status = .Error
                    throw error
                }
            }
        }
        return count
    }
    
    
    public func readString() throws -> String? {
        buffer!.length = 0
        let length = try readData(buffer!)
        if length > 0 {
            return StringUtils.fromUtf8String(buffer!)
        }
        else {
            return nil
        }
    }
    
    
    private func freeHttpParser () {
        httpParser?.delegate = nil
        httpParser = nil
    }
    
    
    func onUrl(data: NSData) {
        url.appendData(data)
    }
    
    
    func onHeaderField (data: NSData) {
        if lastHeaderWasAValue {
            addHeader()
        }
        lastHeaderField.appendData(data)
        lastHeaderWasAValue = false
    }
    
    
    func onHeaderValue (data: NSData) {
        lastHeaderValue.appendData(data)
        lastHeaderWasAValue = true
    }
    
    private func addHeader() {
        let headerKey = StringUtils.fromUtf8String(lastHeaderField)!
        let headerValue = StringUtils.fromUtf8String(lastHeaderValue)!
        
        rawHeaders.append(headerKey)
        rawHeaders.append(headerValue)
        headers[headerKey] = headerValue
        
        lastHeaderField.length = 0
        lastHeaderValue.length = 0
    }
    
    
    func onBody (data: NSData) {
        self.bodyChunk.appendData(data)
    }
    
    
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16) {
        httpVersionMajor = versionMajor
        httpVersionMinor = versionMinor
        self.method = method
        
        if  lastHeaderWasAValue  {
            addHeader()
        }
        
        status = .HeadersComplete
    }
    
    
    func onMessageBegin() {
    }
    
    
    func onMessageComplete() {
        status = .MessageComplete
        freeHttpParser()
    }
    
    func reset() {
    }
    
}

protocol IncomingMessageHelper {
    func readDataHelper(data: NSMutableData) throws -> Int
}
