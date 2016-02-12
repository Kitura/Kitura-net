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


import sys
import BlueSocket

import Foundation

public class IncomingMessage : HttpParserDelegate, BlueSocketReader {

    private static let BUFFER_SIZE = 2000

    public var httpVersionMajor: UInt16?

    public var httpVersionMinor: UInt16?

    public var headers = [String:String]()

    public var rawHeaders = [String]()

    public var method: String = "" // TODO: enum?

    public var urlString = ""

    public var url = NSMutableData()

    // TODO: trailers

    private var lastHeaderWasAValue = false

    private var lastHeaderField = NSMutableData()

    private var lastHeaderValue = NSMutableData()

    private var httpParser: HttpParser?

    private var status = Status.Initial

    private var bodyChunk = BufferList()

    private weak var helper: IncomingMessageHelper?

    private var ioBuffer = NSMutableData(capacity: BUFFER_SIZE)
    private var buffer = NSMutableData(capacity: BUFFER_SIZE)


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


    private func freeHttpParser () {
        httpParser?.delegate = nil
        httpParser = nil
    }


    func onUrl(data: NSData) {
        url.appendData(data)
    }


    func onHeaderField (data: NSData) {
        if lastHeaderWasAValue {
            addHeader()
        }
        lastHeaderField.appendData(data)
        lastHeaderWasAValue = false
    }


    func onHeaderValue (data: NSData) {
        lastHeaderValue.appendData(data)
        lastHeaderWasAValue = true
    }

    private func addHeader() {
        let headerKey = StringUtils.fromUtf8String(lastHeaderField)!
        let headerValue = StringUtils.fromUtf8String(lastHeaderValue)!

        rawHeaders.append(headerKey)
        rawHeaders.append(headerValue)
        headers[headerKey] = headerValue

        lastHeaderField.length = 0
        lastHeaderValue.length = 0
    }


    func onBody (data: NSData) {
        self.bodyChunk.appendData(data)
    }


    func onHeadersComplete(method: String, versionMajor: UInt16, versionMinor: UInt16) {
        httpVersionMajor = versionMajor
        httpVersionMinor = versionMinor
        self.method = method

        if  lastHeaderWasAValue  {
            addHeader()
        }

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

protocol IncomingMessageHelper: class {
    func readDataHelper(data: NSMutableData) throws -> Int
}
