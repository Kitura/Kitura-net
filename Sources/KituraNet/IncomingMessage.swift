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

// MARK: IncomingMessage

public class IncomingMessage : HttpParserDelegate, SocketReader {

    ///
    /// Default buffer size used for creating a BufferList
    ///
    private static let BUFFER_SIZE = 2000

    /// 
    /// Major version for HTTP 
    ///
    public private(set) var httpVersionMajor: UInt16?

    ///
    /// Minor version for HTTP
    ///
    public private(set) var httpVersionMinor: UInt16?

    //
    // Storage for headers
    //
    private let headerStorage = HeaderStorage()

    ///
    /// Set of headers who's value is a String
    ///
    public private(set) var headers: SimpleHeaders

    ///
    /// Set of headers who's value is an Array
    ///
    public private(set) var headersAsArrays: ArrayHeaders

    ///
    /// Raw headers before processing
    ///
    public private(set) var rawHeaders = [String]()

    ///
    /// HTTP Method
    ///
    public private(set) var method: String = "" // TODO: enum?

    ///
    /// URL
    ///
    public private(set) var urlString = ""

    ///
    /// Raw URL
    ///
    public private(set) var url = NSMutableData()

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

        headers = SimpleHeaders(storage: headerStorage)
        headersAsArrays = ArrayHeaders(storage: headerStorage)

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
        guard let parser = httpParser where status == .Initial else {
            freeHttpParser()
            callback(.InternalError)
            return
        }

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

    ///
    /// Read data in the message
    ///
    /// - Parameter data: An NSMutableData to hold the data in the message
    ///
    /// - Returns: the number of bytes read
    ///
    public func read(into data: NSMutableData) throws -> Int {
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
    /// Read all data in the message
    ///
    /// - Parameter data: An NSMutableData to hold the data in the message
    ///
    /// - Returns: the number of bytes read
    ///
    public func readAllData(data: NSMutableData) throws -> Int {
        var length = try read(into: data)
        var bytesRead = length
        while length != 0 {
            length = try read(into: data)
            bytesRead += length
        }
        return bytesRead
    }

    ///
    /// Read the string
    ///
    /// - Throws: TODO ???
    /// - Returns: an Optional string
    ///
    public func readString() throws -> String? {

        buffer!.length = 0
        let length = try read(into: buffer!)
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

        headerStorage.addHeader(headerKey, headerValue: headerValue)

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
        urlString = StringUtils.fromUtf8String(url) ?? ""

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

//
// Private class for Header storage
//
internal class HeaderStorage {
    //
    // Storage for headers who's value is a String
    //
    internal var simpleHeaders = [String:String]()

    //
    // Storage for headers who's value is an Array of Strings
    //
    internal var arrayHeaders = [String: [String]]()

    func addHeader(headerKey: String, headerValue: String) {
        let headerKeyLowerCase = headerKey.bridge().lowercaseString
        // Determine how to handle the header (i.e. simple header array header,...)
        switch(headerKeyLowerCase) {

            // Headers with an array value (can appear multiple times, but can't be merged)
            //
            case "set-cookie":
                var oldArray = arrayHeaders[headerKeyLowerCase] ?? [String]()
                oldArray.append(headerValue)
                arrayHeaders[headerKeyLowerCase] = oldArray
                break

            // Headers with a simple value that are not merged (i.e. duplicates dropped)
            // https://mxr.mozilla.org/mozilla/source/netwerk/protocol/http/src/nsHttpHeaderArray.cpp
            //
            case "content-type", "content-length", "user-agent", "referer", "host",
                    "authorization", "proxy-authorization", "if-modified-since",
                    "if-unmodified-since", "from", "location", "max-forwards",
                    "retry-after", "etag", "last-modified", "server", "age", "expires":
                if  simpleHeaders[headerKeyLowerCase]  == nil  {
                    // ignore the header if we already had one with this key
                    simpleHeaders[headerKeyLowerCase] = headerValue
                }
                break

            // Headers with a simple value that can be merged
            //
            default:
                if  let oldValue = simpleHeaders[headerKeyLowerCase]  {
                    simpleHeaders[headerKeyLowerCase] = oldValue + ", " + headerValue
                }
                else {
                    simpleHeaders[headerKeyLowerCase] = headerValue
                }
                break
        }
    }
}

//
// Class to "simulate" Dictionary access of headers with simple values
//
public class SimpleHeaders {
    internal let storage: HeaderStorage

    private init(storage: HeaderStorage) {
        self.storage = storage
    }

    public subscript(key: String) -> String? {
        let keyLowercase = key.bridge().lowercaseString
        var result = storage.simpleHeaders[keyLowercase]
        if  result == nil  {
            if  let entry = storage.arrayHeaders[keyLowercase]  {
                result = entry[0]
            }
        }
        return result
    }
}

extension SimpleHeaders: SequenceType {
    public typealias Generator = SimpleHeadersGenerator

    public func generate() -> SimpleHeaders.Generator {
        return SimpleHeaders.Generator(self)
    }
}

public struct SimpleHeadersGenerator: GeneratorType {
    public typealias Element = (String, String)

    private var simpleGenerator: DictionaryGenerator<String, String>
    private var arrayGenerator: DictionaryGenerator<String, [String]>

    init(_ simpleHeaders: SimpleHeaders) {
        simpleGenerator = simpleHeaders.storage.simpleHeaders.generate()
        arrayGenerator = simpleHeaders.storage.arrayHeaders.generate()
    }

    public mutating func next() -> SimpleHeadersGenerator.Element? {
        var result = simpleGenerator.next()
        if  result == nil  {
            if  let arrayElem = arrayGenerator.next()  {
                let (arrayKey, arrayValue) = arrayElem
                result = (arrayKey, arrayValue[0])
            }
        }
        return result
    }
}

//
// Class to "simulate" Dictionary access of headers with array values
//
public class ArrayHeaders {
    private let storage: HeaderStorage

    private init(storage: HeaderStorage) {
        self.storage = storage
    }

    public subscript(key: String) -> [String]? {
        let keyLowercase = key.bridge().lowercaseString
        var result = storage.arrayHeaders[keyLowercase]
        if  result == nil  {
            if  let entry = storage.simpleHeaders[keyLowercase]  {
                result = entry.bridge().componentsSeparatedByString(", ")
            }
        }
        return result
    }
}

extension ArrayHeaders: SequenceType {
    public typealias Generator = ArrayHeadersGenerator

    public func generate() -> ArrayHeaders.Generator {
        return ArrayHeaders.Generator(self)
    }
}

public struct ArrayHeadersGenerator: GeneratorType {
    public typealias Element = (String, [String])

    private var arrayGenerator: DictionaryGenerator<String, [String]>
    private var simpleGenerator: DictionaryGenerator<String, String>

    init(_ arrayHeaders: ArrayHeaders) {
        arrayGenerator = arrayHeaders.storage.arrayHeaders.generate()
        simpleGenerator = arrayHeaders.storage.simpleHeaders.generate()
    }

    public mutating func next() -> ArrayHeadersGenerator.Element? {
        var result = arrayGenerator.next()
        if  result == nil  {
            if  let simpleElem = simpleGenerator.next()  {
                let (simpleKey, simpleValue) = simpleElem
                result = (simpleKey, simpleValue.bridge().componentsSeparatedByString(", "))
            }
        }
        return result
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
