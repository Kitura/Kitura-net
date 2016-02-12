/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import BlueSocket

import Foundation

public class ServerResponse : BlueSocketWriter {
    private var socket: BlueSocket?
    
    private var startFlushed = false
    
    private var singleHeaders: [String: String] = [:]
    private var multiHeaders: [String: [String]] = [:]
    
    public var status = HttpStatusCode.OK.rawValue
    public var statusCode: HttpStatusCode? {
        get {
            return HttpStatusCode(rawValue: status)
        }
        set (newValue) {
            if let newValue = newValue where !startFlushed {
                status = newValue.rawValue
            }
        }
    }
    
    init(socket: BlueSocket) {
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
        if  let socket = socket {
            try flushStart()
            try socket.writeString(text)
        }
    }
    
    public func writeData(data: NSData) throws {
        if  let socket = socket {
            try flushStart()
            try socket.writeData(data)
        }
    }
    
    public func end(text: String) throws {
        try writeString(text)
        try end()
    }
    
    public func end() throws {
        if  let socket = socket {
            try flushStart()
            socket.close()
        }
        socket = nil
    }
    
    private func flushStart() throws {
        if  let socket = socket where !startFlushed  {
            
            try socket.writeString("HTTP/1.1 ")
            try socket.writeString(String(status))
            try socket.writeString(" ")
            var statusText = Http.statusCodes[status]
            if  statusText == nil {
                statusText = ""
            }
            try socket.writeString(statusText!)
            try socket.writeString("\r\n")
            
            for (key, value) in singleHeaders {
                try socket.writeString(key)
                try socket.writeString(": ")
                try socket.writeString(value)
                try socket.writeString("\r\n")
            }
            for (key, valueSet) in multiHeaders {
                for value in valueSet {
                    try socket.writeString(key)
                    try socket.writeString(": ")
                    try socket.writeString(value)
                    try socket.writeString("\r\n")
                }
            }
            
            try socket.writeString("\r\n")
            
            startFlushed = true
        }
    }
}
