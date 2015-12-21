//
//  HttpParser.swift
//  EnterpriseSwift
//
//  Created by Ira Rosen on 14/10/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import sys
//import Chttp_parser
import http_parser_helper

class HttpParser {
    
    var parser: http_parser
    var settings: http_parser_settings
    
    var delegate: HttpParserDelegate? {
        didSet {
            if let _ = delegate {
                withUnsafeMutablePointer(&delegate) { ptr in
                    self.parser.data = UnsafeMutablePointer<Void>(ptr)
                }
            }
        }
    }
    
    var upgrade = 1

    init(isRequest: Bool) {
        parser = http_parser()
        settings = http_parser_settings()

        settings.on_url = { (parser, chunk, length) -> Int32 in
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            var arr = [UInt8](count: length, repeatedValue: 0)
            memcpy(&arr, chunk, length)
            let url = StringUtils.fromUtf8String(arr, withLength: length)
            p.memory?.onUrl(arr, urlString: url)
            return 0
        }
        
        settings.on_header_field = { (parser, chunk, length) -> Int32 in
            if let data = StringUtils.fromUtf8String(UnsafePointer<UInt8>(chunk), withLength: length) {
                let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
                p.memory?.onHeaderField(data as String)
            }
            return 0
        }
        
        settings.on_header_value = { (parser, chunk, length) -> Int32 in
            if let data = StringUtils.fromUtf8String(UnsafePointer<UInt8>(chunk), withLength: length) {
                let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
                p.memory?.onHeaderValue(data as String)
            }
            return 0
        }
        
        settings.on_body = { (parser, chunk, length) -> Int32 in
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            var arr = [UInt8](count: length, repeatedValue: 0)
            memcpy(&arr, chunk, length)
            p.memory?.onBody(arr)
           
            return 0
        }
        
        settings.on_headers_complete = { (parser) -> Int32 in
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            let method = StringUtils.fromUtf8String(UnsafePointer<UInt8>(get_method(parser)))
            p.memory?.onHeadersComplete(method!, versionMajor: parser.memory.http_major, versionMinor: parser.memory.http_minor)
            
            return 0
        }
        
        settings.on_message_begin = { (parser) -> Int32 in
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            p.memory?.onMessageBegin()
            
            return 0
        }
        
        settings.on_message_complete = { (parser) -> Int32 in
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            if get_status_code(parser) == 100 {
                p.memory?.reset()
            }
            else {
                p.memory?.onMessageComplete()
            }
            
            return 0
        }
        
        http_parser_init(&parser, isRequest ? HTTP_REQUEST : HTTP_RESPONSE)

    }
    
    
    func execute (data: [UInt8], length: Int) -> (Int, UInt32) {
        let nparsed = http_parser_execute(&parser, &settings, UnsafePointer<Int8>(data), length)
        let upgrade = get_upgrade_value(&parser)
        return (nparsed, upgrade)
    }    
}


protocol HttpParserDelegate: class {
    func onUrl(url:[UInt8], urlString: String?)
    func onHeaderField(url: String)
    func onHeaderValue(url: String)
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16)
    func onMessageBegin()
    func onMessageComplete()
    func onBody(body: [UInt8])
    func reset()
}
