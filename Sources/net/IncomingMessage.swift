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
import BlueSocket

import Foundation

// MARK: IncomingMessage

public class IncomingMessage : HttpParserDelegate, BlueSocketReader {

    ///
    /// Default buffer size used for creating a BufferList
    ///
    private static let BUFFER_SIZE = 2000

    /// 
    /// Major version for HTTP 
    ///
    public var httpVersionMajor: UInt16?

    ///
    /// Minor version for HTTP
    ///
    public var httpVersionMinor: UInt16?

    ///
    /// List of String to String tuples
    ///
    public var headers = [String:String]()

    ///
    /// Raw headers before processing
    ///
    public var rawHeaders = [String]()

    ///
    /// Method
    ///
    public var method: String = "" // TODO: enum?

    ///
    /// URL
    ///
    public var urlString = ""

    ///
    /// Raw URL
    ///
    public var url = NSMutableData()

    // MARK: - Private
    
    // TODO: trailers

    ///
    /// TODO: ???
    ///
    private var lastHeaderWasAValue = false

    ///
    /// TODO: ???
    ///
    private var lastHeaderField = NSMutableData()

    ///
    /// TODO: ???
    ///
    private var lastHeaderValue = NSMutableData()

    ///
    /// TODO: ???
    ///
    private var httpParser: HttpParser?

    ///
    /// TODO: ???
    ///
    private var status = Status.Initial

    ///
    /// TODO: ???
    ///
    private var bodyChunk = BufferList()

    ///
    /// TODO: ???
    ///
    private weak var helper: IncomingMessageHelper?

    ///
    /// TODO: ???
    ///
    private var ioBuffer = NSMutableData(capacity: BUFFER_SIZE)
    
    ///
    /// TODO: ???
    ///
    private var buffer = NSMutableData(capacity: BUFFER_SIZE)


    ///
    /// List of status states
    ///
    private enum Status {
        
        case Initial
        case HeadersComplete
        case MessageComplete
        case Error
        
    }


    ///
    /// Http parser error types
    ///
    public enum HttpParserErrorType {
        
        case Success
        case ParsedLessThanRead
        case UnexpectedEOF
        case InternalError // TODO
        
    }

    ///
    /// Initializes a new IncomingMessage
    ///
    /// - Parameter isRequest: whether this message is a request
    ///
    /// - Returns: an IncomingMessage instance
    ///
    init (isRequest: Bool) {
        httpParser = HttpParser(isRequest: isRequest)
        httpParser!.delegate = self
    }

    ///
    /// Sets a helper delegate
    ///
    /// - Parameter helper: the IncomingMessageHelper
    ///
    func setup(helper: IncomingMessageHelper) {
        self.helper = helper
    }


    ///
    /// Parse the message
    ///
    /// - Parameter callback: (HttpParserErrorType) -> Void closure
    ///
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
                            status = .Error
                            callback(.ParsedLessThanRead)
                        }
                    }
                    else {
                        /* Handle unexpected EOF. Usually just close the connection. */
                        freeHttpParser()
                        status = .Error
                        callback(.UnexpectedEOF)
                    }
                }
                catch {
                    /* Handle error. Usually just close the connection. */
                    freeHttpParser()
                    status = .Error
                    callback(.UnexpectedEOF)
                }
            }
            if status != .Error {
                callback(.Success)
            }
        }
        else {
            freeHttpParser()
            callback(.InternalError)
        }
    }

    ///
    /// Read the data in the message
    ///
    /// - Parameter data: the data in the message
    /// 
    /// - Returns: the number of bytes read
    ///
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

    ///
    /// Read the string
    ///
    /// - Throws: TODO ???
    /// - Returns: an Optional string
    ///
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

    ///
    /// Free the httpParser from the IncomingMessage
    ///
    private func freeHttpParser () {
        
        httpParser?.delegate = nil
        httpParser = nil
        
    }


    ///
    /// Instructions for when reading URL portion
    ///
    /// - Parameter data: the data
    ///
    func onUrl(data: NSData) {
        url.appendData(data)
    }


    ///
    /// Instructions for when reading header field
    ///
    /// - Parameter data: the data
    ///
    func onHeaderField (data: NSData) {
        
        if lastHeaderWasAValue {
            addHeader()
        }
        lastHeaderField.appendData(data)
        lastHeaderWasAValue = false
        
    }

    ///
    /// Instructions for when reading a header value
    ///
    /// - Parameter data: the data
    ///
    func onHeaderValue (data: NSData) {
        
        lastHeaderValue.appendData(data)
        lastHeaderWasAValue = true
        
    }

    ///
    /// Set the header key-value pair 
    ///
    private func addHeader() {
        
        let headerKey = StringUtils.fromUtf8String(lastHeaderField)!
        let headerValue = StringUtils.fromUtf8String(lastHeaderValue)!

        rawHeaders.append(headerKey)
        rawHeaders.append(headerValue)
        headers[headerKey] = headerValue

        lastHeaderField.length = 0
        lastHeaderValue.length = 0
        
    }

    /// 
    /// Instructions for when reading the body of the message 
    ///
    /// - Parameter data: the data
    ///
    func onBody (data: NSData) {
        
        self.bodyChunk.appendData(data)
        
    }

    ///
    /// Instructions for when the headers have been finished being parsed.
    ///
    /// - Parameter method: the HTTP method
    /// - Parameter versionMajor: major version of HTTP
    /// - Parameter versionMinor: minor version of HTTP 
    ///
    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16) {
        
        httpVersionMajor = versionMajor
        httpVersionMinor = versionMinor
        self.method = method

        if  lastHeaderWasAValue  {
            addHeader()
        }

        status = .HeadersComplete
        
    }


    ///
    /// Instructions for when beginning to read a message 
    ///
    func onMessageBegin() {
    }


    ///
    /// Instructions for when done reading the message 
    ///
    func onMessageComplete() {
        
        status = .MessageComplete
        freeHttpParser()
        
    }

    ///
    /// instructions for when reading is reset
    ///
    func reset() {
    }

}

///
/// Protocol for IncomingMessageHelper
protocol IncomingMessageHelper: class {
    
    ///
    /// TODO: ???
    ///
    func readDataHelper(data: NSMutableData) throws -> Int
    
}
