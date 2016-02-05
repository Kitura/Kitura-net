//
//  HttpParser.swift
//  EnterpriseSwift
//
//  Created by Ira Rosen on 14/10/15.
//  Copyright © 2015 IBM. All rights reserved.
//

import sys
import http_parser_helper
import Foundation

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
            let data = NSData(bytes: chunk, length: length)
            p.memory?.onUrl(data)
            return 0
        }
        
        settings.on_header_field = { (parser, chunk, length) -> Int32 in
            let data = NSData(bytes: chunk, length: length)
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            p.memory?.onHeaderField(data)
            return 0
        }
        
        settings.on_header_value = { (parser, chunk, length) -> Int32 in
            let data = NSData(bytes: chunk, length: length)
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            p.memory?.onHeaderValue(data)
            return 0
        }
        
        settings.on_body = { (parser, chunk, length) -> Int32 in
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            let data = NSData(bytes: chunk, length: length)
            p.memory?.onBody(data)
           
            return 0
        }
        
        settings.on_headers_complete = { (parser) -> Int32 in
            let p = UnsafePointer<HttpParserDelegate?>(parser.memory.data)
            // TODO: Clean and refactor
            //let method = String( get_method(parser))
            let po =  get_method(parser)
            var message = ""
            var i = 0
            while((po+i).memory != Int8(0)) {
                message += String(UnicodeScalar(UInt8((po+i).memory)))
                i += 1
            }
            p.memory?.onHeadersComplete(message, versionMajor: parser.memory.http_major, versionMinor: parser.memory.http_minor)
            
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
    
    
    func execute (data: UnsafePointer<Int8>, length: Int) -> (Int, UInt32) {
        let nparsed = http_parser_execute(&parser, &settings, data, length)
        let upgrade = get_upgrade_value(&parser)
        return (nparsed, upgrade)
    }    
}


protocol HttpParserDelegate: class {
    func onUrl(url:NSData)
    func onHeaderField(data: NSData)
    func onHeaderValue(data: NSData)
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16)
    func onMessageBegin()
    func onMessageComplete()
    func onBody(body: NSData)
    func reset()
}
