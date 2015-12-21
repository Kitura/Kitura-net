//
//  ClientRequest.swift
//  Pods
//
//  Created by Samuel Kallner on 11/18/15.
//
//

import io
import sys

//import curl
import CurlHelpers


public class ClientRequest: Writer {
    
    static private var lock = 0

    public var headers = [String: String]()
    
    private var url: String
    private var method: String = "get"
    private var userName: String? = nil
    private var password: String? = nil
    
    private var maxRedirects = 10
    private var handle: UnsafeMutablePointer<Void>?
    private var headersList: UnsafeMutablePointer<curl_slist> = nil
    private var writeBuffers = BufferList()
    
    private var response = ClientResponse()
    private var callback: ClientRequestCallback
    
    init(url: String, callback: ClientRequestCallback) {
        self.url = url
        self.callback = callback
    }
    
    init(options: [ClientRequestOptions], callback: ClientRequestCallback) {
        self.callback = callback
        
        var theProtocol = "http://"
        var hostName = "localhost"
        var path = "/"
        var port:Int16 = 80
        
        for  option in options  {
            switch(option) {
                case .Method(let method):
                    self.method = method
                case .Protocol(let prot):
                    theProtocol = prot
                case .Hostname(let host):
                    hostName = host
                case .Port(let thePort):
                    port = thePort
                case .Path(let thePath):
                    path = thePath
                case .Headers(let headers):
                    for (key, value) in headers {
                        self.headers[key] = value
                    }
                case .Username(let userName):
                    self.userName = userName
                case .Password(let password):
                    self.password = password
                case .MaxRedirects(let maxRedirects):
                    self.maxRedirects = maxRedirects
            }
        }
        
        url = theProtocol + hostName + ":" + String(port) + path
    }
    
    deinit {
        if  let handle = handle  {
            curl_easy_cleanup(handle)
        }
        if  headersList != nil  {
            curl_slist_free_all(headersList)
        }
    }
    
    public func writeString(data: String) {
        var buffer = StringUtils.toUtf8String(data)
        if  buffer != nil {
            let length = Int(strlen(UnsafePointer<Int8>(buffer!)))
            writeBuffer(&buffer!, withLength: length)
        }
    }
    
    public func writeBuffer(inout buffer: [UInt8], withLength length: Int) {
        let buf = [UInt8](count: length, repeatedValue: 0)
        memcpy(UnsafeMutablePointer<UInt8>(buf), buffer, length)
        writeBuffers.addBuffer(buf)
    }
    
    public func end(data: String) {
        writeString(data)
        end()
    }
    
    public func end() {
        SysUtils.doOnce(&ClientRequest.lock) {
            curl_global_init(Int(CURL_GLOBAL_SSL))
        }
        
        var callCallback = true
        var urlBuf = StringUtils.toUtf8String(url)
        if  let _ = urlBuf {
            prepareHandle(&urlBuf!)
            
            let invoker = CurlInvoker(handle: handle!, maxRedirects: maxRedirects)
            invoker.delegate = self

            var code = invoker.invoke()
            if  code == CURLE_OK  {
                code = curlHelperGetInfoLong(handle!, CURLINFO_RESPONSE_CODE, &response.status)
                if  code == CURLE_OK  {
                    response.parse() {status in
                        switch(status) {
                            case .Success:
                                self.callback(response: self.response)
                                callCallback = false
                    
                            default: break
                        }
                    }
                }
            }
        }
        if  callCallback  {
            callback(response: nil)
        }
    }
    
    private func prepareHandle(inout urlBuf: [UInt8]) {
        handle = curl_easy_init()
        curlHelperSetOptString(handle!, CURLOPT_URL, UnsafeMutablePointer<Int8>(urlBuf))
        setMethod()
        let count = writeBuffers.count
        if  count != 0  {
            curlHelperSetOptInt(handle!, CURLOPT_POSTFIELDSIZE, count)
        }
        setupHeaders()
    }
    
    private func setMethod() {
        let methodUpperCase = method.uppercaseString
        switch(methodUpperCase) {
            case "GET":
                curlHelperSetOptBool(handle!, CURLOPT_HTTPGET, CURL_TRUE)
            case "POST":
                curlHelperSetOptBool(handle!, CURLOPT_POST, CURL_TRUE)
            case "PUT":
                curlHelperSetOptBool(handle!, CURLOPT_PUT, CURL_TRUE)
            default:
                let methodCstring = StringUtils.toUtf8String(methodUpperCase)!
                curlHelperSetOptString(handle!, CURLOPT_CUSTOMREQUEST, UnsafeMutablePointer<Int8>(methodCstring))
        }
    }
    
    private func setupHeaders() {
        for (headerKey, headerValue) in headers {
            let headerString = StringUtils.toUtf8String("\(headerKey): \(headerValue)")
            if  let headerString = headerString  {
                headersList = curl_slist_append(headersList, UnsafePointer<Int8>(headerString))
            }
        }
        curlHelperSetOptHeaders(handle!, headersList)
    }
}

extension ClientRequest: CurlInvokerDelegate {
    private func curlWriteCallback(buf: UnsafeMutablePointer<Int8>, size: Int) -> Int {
        let buffer = [UInt8](count: size, repeatedValue: 0)
        memcpy(UnsafeMutablePointer<UInt8>(buffer), buf, size)
        response.responseBuffers.addBuffer(buffer)
        return size
    }
    
    private func curlReadCallback(buf: UnsafeMutablePointer<Int8>, size: Int) -> Int {
        var lclBuffer = [UInt8](count: size, repeatedValue: 0)
        let count = writeBuffers.fillBuffer(&lclBuffer)
        memcpy(buf, UnsafePointer<UInt8>(lclBuffer), count)
        return count
    }
    
    private func prepareForRedirect() {
        response.responseBuffers.reset()
        writeBuffers.rewind()
    }
}

public enum ClientRequestOptions {
    case Method(String), Protocol(String), Hostname(String), Port(Int16), Path(String),
    Headers([String: String]), Username(String), Password(String), MaxRedirects(Int)
}

public typealias ClientRequestCallback = (response: ClientResponse?) -> Void

private class CurlInvoker {
    private var handle: UnsafeMutablePointer<Void>
    private weak var delegate: CurlInvokerDelegate? = nil
    private let maxRedirects: Int
    
    private init(handle: UnsafeMutablePointer<Void>, maxRedirects: Int) {
        self.handle = handle
        self.maxRedirects = maxRedirects
    }
    
    private func invoke() -> CURLcode {
        var rc: CURLcode = CURLE_FAILED_INIT
        if  let _ = delegate {
            withUnsafeMutablePointer(&delegate) {ptr in
                self.prepareHandle(ptr)
        
                var redirected = false
                var redirectCount = 0
                repeat {
                    rc = curl_easy_perform(handle)
        
                    if  rc == CURLE_OK  {
                        var redirectUrl: UnsafeMutablePointer<Int8> = nil
                        let infoRc = curlHelperGetInfoCString(handle, CURLINFO_REDIRECT_URL, &redirectUrl)
                        if  infoRc == CURLE_OK {
                            if  redirectUrl != nil  {
                                curlHelperSetOptString(handle, CURLOPT_URL, redirectUrl)
                                redirected = true
                                delegate?.prepareForRedirect()
                                redirectCount++
                            }
                            else {
                                redirected = false
                            }
                        }
                    }
                } while  rc == CURLE_OK  &&  redirected  &&  redirectCount < maxRedirects
            }
        }
        return rc
    }

    private func prepareHandle(ptr: UnsafeMutablePointer<CurlInvokerDelegate?>) {
        
        curlHelperSetOptReadFunc(handle, ptr) { (buf: UnsafeMutablePointer<Int8>, size: Int, nMemb: Int, privateData: UnsafeMutablePointer<Void>) -> Int in
                    
                let p = UnsafePointer<CurlInvokerDelegate?>(privateData)
                return (p.memory?.curlReadCallback(buf, size: size*nMemb))!
        }
                
        curlHelperSetOptWriteFunc(handle, ptr) { (buf: UnsafeMutablePointer<Int8>, size: Int, nMemb: Int, privateData: UnsafeMutablePointer<Void>) -> Int in
                    
                let p = UnsafePointer<CurlInvokerDelegate?>(privateData)
                return (p.memory?.curlWriteCallback(buf, size: size*nMemb))!
        }
    }
}

private protocol CurlInvokerDelegate: class {
    func curlWriteCallback(buf: UnsafeMutablePointer<Int8>, size: Int) -> Int
    func curlReadCallback(buf: UnsafeMutablePointer<Int8>, size: Int) -> Int
    func prepareForRedirect()
}