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

import KituraSys
import Socket

import Foundation

// MARK: ServerResponse

public class ServerResponse : SocketWriter {

    ///
    /// Socket for the ServerResponse
    ///
    private var socket: Socket?

    ///
    /// Size of buffer
    ///
    private let BUFFER_SIZE = 2000

    ///
    /// Buffer for HTTP response line, headers, and short bodies
    ///
    private var buffer: NSMutableData

    ///
    /// Whether or not the HTTP response line and headers have been flushed.
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
    private var status = HttpStatusCode.OK.rawValue

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
        buffer = NSMutableData(capacity: BUFFER_SIZE)!
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

        if  socket != nil  {
            try flushStart()
            try writeToSocketThroughBuffer(text: string)
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
            if  buffer.length + data.length > BUFFER_SIZE  &&  buffer.length != 0  {
                try socket.write(from: buffer)
                buffer.length = 0
            }
            if  data.length > BUFFER_SIZE {
                try socket.write(from: data)
            }
            else {
                buffer.append(data)
            }
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
            if  buffer.length > 0  {
                try socket.write(from: buffer)
            }
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

        if  socket == nil  ||  startFlushed  {
            return
        }

        try writeToSocketThroughBuffer(text: "HTTP/1.1 ")
        try writeToSocketThroughBuffer(text: String(status))
        try writeToSocketThroughBuffer(text: " ")
        var statusText = Http.statusCodes[status]

        if  statusText == nil {
            statusText = ""
        }

        try writeToSocketThroughBuffer(text: statusText!)
        try writeToSocketThroughBuffer(text: "\r\n")

        for (key, value) in singleHeaders {
            try writeToSocketThroughBuffer(text: key)
            try writeToSocketThroughBuffer(text: ": ")
            try writeToSocketThroughBuffer(text: value)
            try writeToSocketThroughBuffer(text: "\r\n")
        }

        for (key, valueSet) in multiHeaders {
            for value in valueSet {
                try writeToSocketThroughBuffer(text: key)
                try writeToSocketThroughBuffer(text: ": ")
                try writeToSocketThroughBuffer(text: value)
                try writeToSocketThroughBuffer(text: "\r\n")
            }
        }

        try writeToSocketThroughBuffer(text: "\r\n")
        startFlushed = true
    }

    ///
    /// Function to write Strings to the socket through the buffer
    ///
    private func writeToSocketThroughBuffer(text: String) throws {
        guard let socket = socket,
              let utf8Data = StringUtils.toUtf8String(text) else {
            return
        }

        if  buffer.length + utf8Data.length > BUFFER_SIZE  &&  buffer.length != 0  {
            try socket.write(from: buffer)
            buffer.length = 0
        }
        if  utf8Data.length > BUFFER_SIZE {
            try socket.write(from: utf8Data)
        }
        else {
            buffer.append(utf8Data)
        }
    }
}
