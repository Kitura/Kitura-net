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
    public var headers: [String: [String]] = [:]
    
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
        headers["Date"] = [SpiUtils.httpDate()]
        
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

        for (key, valueSet) in headers {
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
