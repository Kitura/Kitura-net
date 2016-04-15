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

import Socket

import Foundation

// MARK: ServerResponse

public class ServerResponse : SocketWriter {

    ///
    /// Socket for the ServerResponse
    ///
    private var socket: Socket?
    
    ///
    /// TODO: ???
    ///
    private var startFlushed = false
    
    ///
    /// TODO: ???
    ///
    private var singleHeaders: [String: String] = [:]
    
    ///
    /// TODO: ???
    ///
    private var multiHeaders: [String: [String]] = [:]
    
    ///
    /// Status code
    ///
    public var status = HttpStatusCode.OK.rawValue
    
    ///
    /// Status code
    ///
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
    
    ///
    /// Initializes a ServerResponse instance
    ///
    init(socket: Socket) {
        
        self.socket = socket
        setHeader("Date", value: SpiUtils.httpDate())
        
    }
    
    ///
    /// Get a specific headers for the response by key
    ///
    /// - Parameter key: the header key
    ///
    public func getHeader(_ key: String) -> String? {
        
        return singleHeaders[key]
        
    }
    
    ///
    /// Get all values on a specific key
    ///
    /// - Parameter key: the header key
    ///
    /// - Returns: a list of String values
    ///
    public func getHeaders(_ key: String) -> [String]? {
        
        return multiHeaders[key]
        
    }
    
    ///
    /// Set the value for a header
    ///
    /// - Parameter key: key 
    /// - Parameter value: the value
    ///
    public func setHeader(_ key: String, value: String) {
        singleHeaders[key] = value
        multiHeaders.removeValue(forKey: key)
    }

    ///
    /// Set the value for a header (list)
    ///
    /// - Parameter key: key
    /// - Parameter value: the value
    ///
    public func setHeader(_ key: String, value: [String]) {
        multiHeaders[key] = value
        singleHeaders.removeValue(forKey: key)
    }

    ///
    /// Append a value to the header
    ///
    /// - Parameter key: the header key
    /// - Parameter value: string value
    ///
    public func append(key: String, value: String) {

        if let singleValue = singleHeaders[key] where multiHeaders.count == 0 {
            multiHeaders[key] = [singleValue, value]
            singleHeaders.removeValue(forKey: key)
        } else if let _ = multiHeaders[key] {
            multiHeaders[key]!.append(value)
        } else {
            setHeader(key, value: value)
        }
    }

    ///
    /// Append values to the header
    ///
    /// - Parameter key: the header key
    /// - Parameter value: array of string values
    ///
    public func append(key: String, value: [String]) {

        if let singleValue = singleHeaders[key] where multiHeaders.count == 0 {
            multiHeaders[key] = [singleValue] + value
            singleHeaders.removeValue(forKey: key)
        } else if let _ = multiHeaders[key] {
            multiHeaders[key]! = multiHeaders[key]! + value
        } else {
            if value.count == 1 {
                setHeader(key, value: value.first!)
            } else {
                setHeader(key, value: value)
            }
        }
    }
    
    ///
    /// Remove a key from the header
    ///
    /// - Parameter key: key
    ///
    public func removeHeader(key: String) {
        singleHeaders.removeValue(forKey: key)
        multiHeaders.removeValue(forKey: key)
    }
    
    ///
    /// Write a string as a response 
    ///
    /// - Parameter string: String data to be written.
    ///
    /// - Throws: ???
    ///
    public func write(from string: String) throws {
        
        if  let socket = socket {
            try flushStart()
            try socket.write(from: string)
        }
        
    }
    
    ///
    /// Write data as a response
    ///
    /// - Parameter data: NSMutableData object to contain read data.
    ///
    /// - Returns: Integer representing the number of bytes read.
    ///
    /// - Throws: ???
    ///
    public func write(from data: NSData) throws {
        
        if  let socket = socket {
            try flushStart()
            try socket.write(from: data)
        }
        
    }
    
    ///
    /// End the response
    ///
    /// - Parameter text: String to write out socket
    ///
    /// - Throws: ???
    ///
    public func end(text: String) throws {
        try write(from: text)
        try end()
    }
    
    ///
    /// End sending the response
    ///
    /// - Throws: ???
    ///
    public func end() throws {
        if  let socket = socket {
            try flushStart()
            socket.close()
        }
        socket = nil
    }
    
    ///
    /// Begin flushing the buffer
    ///
    /// - Throws: ???
    ///
    private func flushStart() throws {

        guard let socket = socket where !startFlushed else {
            return
        }

        try socket.write(from: "HTTP/1.1 ")
        try socket.write(from: String(status))
        try socket.write(from: " ")
        var statusText = Http.statusCodes[status]

        if  statusText == nil {
            statusText = ""
        }

        try socket.write(from: statusText!)
        try socket.write(from: "\r\n")

        for (key, value) in singleHeaders {
            try socket.write(from: key)
            try socket.write(from: ": ")
            try socket.write(from: value)
            try socket.write(from: "\r\n")
        }

        for (key, valueSet) in multiHeaders {
            for value in valueSet {
                try socket.write(from: key)
                try socket.write(from: ": ")
                try socket.write(from: value)
                try socket.write(from: "\r\n")
            }
        }

        try socket.write(from: "\r\n")
        startFlushed = true
    }
}
