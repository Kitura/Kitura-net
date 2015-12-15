//
//  IncomingMessage.swift
//  EnterpriseSwift
//
//  Created by Samuel Kallner on 10/20/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import io
import sys
import SwiftyJSON

public class IncomingMessage : HttpParserDelegate, Reader {
    
    private let BUFFER_SIZE = 2000
    
    public var httpVersionMajor: UInt16?
    
    public var httpVersionMinor: UInt16?
    
    public var headers = [String:String]()
    
    public var rawHeaders = [String]()
    
    public var method: String = "" // TODO: enum?
    
    public var urlString = ""
    
    public var url: [UInt8] = []
        
    // TODO: trailers
    
    private var lastHeaderWasAValue = true
    
    private var lastHeaderField: String = ""
    
    private var lastHeaderValue: String = ""
    
    private var httpParser: HttpParser?
    
    private var status = Status.Initial
    
    private var bodyChunk = BufferList()
    
    private var helper: IncomingMessageHelper?
    
    private var ioBuffer: [UInt8]
    private var buffer: [UInt8]
    
    
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
        ioBuffer = [UInt8](count: BUFFER_SIZE, repeatedValue: 0)
        buffer = [UInt8](count: BUFFER_SIZE, repeatedValue: 0)
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
                    let length = try helper!.readBufferHelper(&ioBuffer)
                    if length > 0 {
                        let (nparsed, upgrade) = parser.execute(ioBuffer, length: length)
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
    
    
    public func readBuffer(inout buffer: [UInt8]) throws -> Int {
        var count = bodyChunk.fillBuffer(&buffer)
        if count == 0 {
            if let parser = httpParser where status == .HeadersComplete {
                do {
                    count = try helper!.readBufferHelper(&ioBuffer)
                    if count > 0 {
                        let (nparsed, upgrade) = parser.execute(ioBuffer, length: count)
                        if upgrade == 1 {
                            // TODO: handle new protocol
                        }
                        else if (nparsed != count) {
                            /* Handle error. Usually just close the connection. */
                            freeHttpParser()
                            status = .Error
                        }
                        else {
                            count = bodyChunk.fillBuffer(&buffer)
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
        let length = try readBuffer(&buffer)
        if length > 0 {
            return StringUtils.fromUtf8String(buffer, withLength: length)
        }
        else {
            return nil
        }
    }
    
    
    private func freeHttpParser () {
        httpParser?.delegate = nil
        httpParser = nil
    }
    
    
    func onUrl(url: [UInt8], urlString: String?) {
        self.url += url
        if let urlString = urlString {
            self.urlString += urlString
        }
    }
    
    
    func onHeaderField (data: String) {
        if lastHeaderWasAValue {
            headers[data] = ""
            lastHeaderField = data
            rawHeaders.append(data)
        }
        else {
            headers.removeValueForKey(lastHeaderField)
            lastHeaderField += data
            headers[lastHeaderField] = ""
            rawHeaders[rawHeaders.count-1] = lastHeaderField
        }
        lastHeaderWasAValue = false
    }
    
    
    func onHeaderValue (data: String) {
        if lastHeaderWasAValue {
            if let value = headers[lastHeaderField] {
                let newValue = value + data
                headers[lastHeaderField] = newValue
                lastHeaderValue = newValue
                rawHeaders[rawHeaders.count-1] = lastHeaderValue
            }
        }
        else {
            headers[lastHeaderField] = data
            lastHeaderValue = data
            rawHeaders.append(data)
        }
        lastHeaderWasAValue = true
    }
    
    
    func onBody (data: [UInt8]) {
        self.bodyChunk.addBuffer(data)
    }
    
    
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16) {
        httpVersionMajor = versionMajor
        httpVersionMinor = versionMinor
        self.method = method
        
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
    func readBufferHelper(inout buffer: [UInt8]) throws -> Int
}
