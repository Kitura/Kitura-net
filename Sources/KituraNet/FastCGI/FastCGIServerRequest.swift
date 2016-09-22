/*
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
 */

import Foundation
import Socket

/// The FastCGIServerRequest class implements the `ServerRequest` protocol
/// for incoming HTTP requests that come in over a FastCGI connection.
public class FastCGIServerRequest : ServerRequest {
    
    /// Socket for the request
    private let socket: Socket
    
    /// The IP address of the client
    public private(set) var remoteAddress: String = ""

    /// Major version of HTTP of the request
    public private(set) var httpVersionMajor: UInt16? = 0
    
    /// Minor version of HTTP of the request
    public private(set) var httpVersionMinor: UInt16? = 9
    
    /// The set of headers received with the incoming request
    public var headers = HeadersContainer()
    
    /// The HTTP Method specified in the request
    public private(set) var method: String = ""
    
    /// The URL from the request in string form
    public var urlString : String {
        guard url.count > 0 else {
            return ""
        }
        return String(data: url, encoding: .utf8)!
    }
    
    /// URI Component received from FastCGI
    private var requestUri : String? = nil
    
    /// The URL from the request in UTF-8 form
    public private(set) var url = Data()

    /// Chunk of body read in by the http_parser, filled by callbacks to onBody
    private var bodyChunk = BufferList()

    /// State of incoming message handling
    private var status = Status.initial
    
    /// The request ID established by the FastCGI client.
    public private(set) var requestId : UInt16 = 0
    
    /// An array of request ID's that are not our primary one.
    /// When the main request is done, the FastCGIServer can reject the
    /// extra requests as being unusable.
    public private(set) var extraRequestIds : [UInt16] = []
    
    /// Some defaults
    private static let defaultMethod : String = "GET"
    
    /// List of status states
    private enum Status {
        case initial
        case requestStarted
        case headersComplete
        case requestComplete
    }
    
    /// HTTP parser error types
    public enum FastCGIParserErrorType {
        case success
        case protocolError
        case invalidType
        case clientDisconnect
        case unsupportedRole
        case internalError
    }
    
    /// Initialize a `FastCGIServerRequest` instance
    ///
    /// - Parameter socket: The socket to read the request from.
    required public init (socket: Socket) {
        self.socket = socket
    }
    
    /// Read data from the body of the request
    ///
    /// - Parameter data: A Data struct to hold the data read in.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket.
    /// - Returns: The number of bytes read.
    public func read(into data: inout Data) throws -> Int {
        return bodyChunk.fill(data: &data)
    }
    
    /// Read all of the data in the body of the request
    ///
    /// - Parameter data: A Data struct to hold the data read in.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket.
    /// - Returns: The number of bytes read.
    public func readAllData(into data: inout Data) throws -> Int {
        return bodyChunk.fill(data: &data)
    }
    
    /// Read a string from the body of the request.
    ///
    /// - Throws: Socket.error if an error occurred while reading from the socket.
    /// - Returns: An Optional string.
    public func readString() throws -> String? {
        var data = Data()
        let bytes : Int = bodyChunk.fill(data: &data)
        
        if bytes > 0 {
            return String(data: data, encoding: .utf8)
        } else {
            return ""
        }
    }
    
    /// Proces the original request URI
    func postProcessUrlParameter() -> Void {
        
        // reset the current url
        //
        url.count = 0
        
        // set the uri
        //
        if let requestUri = requestUri, requestUri.characters.count > 0 {
            
            // use the URI as received
            url.append(requestUri.data(using: .utf8)!)
        }
        else {
            url.append("/".data(using: .utf8)!)
        }
                
    }
    
    /// We've received all the parameters the server is going to send us,
    /// so lets massage these into place and make sure, at worst, sane
    /// defaults are in place.
    private func postProcessParameters() {
        
        // make sure our method is set
        if method.characters.count == 0 {
            method = FastCGIServerRequest.defaultMethod
        }
        
        // make sure our remoteAddress is set
        if remoteAddress.characters.count == 0 {
            remoteAddress = socket.remoteHostname
        }
        
        // assign our URL
        postProcessUrlParameter()
        
    }
    
    /// FastCGI delivers headers that were originally sent by the browser/client
    /// with "HTTP_" prefixed. We want to normalize these out to remove HTTP_
    /// and correct the capitilization (first letter of each word capitilized).
    private func processHttpHeader(_ name: String, value: String, remove: String) {
        
        var processedName : String = name.substring(from:
            name.index(name.startIndex, offsetBy: remove.characters.count))
        
        processedName = processedName.replacingOccurrences(of: "_", with: "-")
        processedName = processedName.capitalized
        
        headers.append(processedName as String, value: value)
    }
    
    /// Parse the server protocol into a major and minor version
    private func processServerProtocol(_ protocolString: String) {
        
        guard protocolString.characters.count > 0 else {
            return
        }
        
        guard protocolString.lowercased().hasPrefix("http/") &&
            protocolString.characters.count > "http/".characters.count else {
            return
        }
        
        let versionPortion : String = protocolString.substring(from:
            protocolString.index(protocolString.startIndex, offsetBy: "http/".characters.count))
        var decimalPosition : Int = 0
        
        for i in versionPortion.characters {
            if i == "." {
                break
            } else {
                decimalPosition += 1
            }
        }
        
        var majorVersion : UInt16? = nil
        var minorVersion : UInt16? = nil
        
        // get major version
        if decimalPosition > 0 {
            let majorPortion : String = versionPortion.substring(to:
                versionPortion.index(versionPortion.startIndex, offsetBy: decimalPosition))
            majorVersion = UInt16(majorPortion)
        }
        
        // get minor version
        if protocolString.characters.count > decimalPosition {
            let minorPortion : String = versionPortion.substring(from:
                versionPortion.index(versionPortion.startIndex, offsetBy: decimalPosition + 1))
            minorVersion = UInt16(minorPortion)
        }
        
        // assign our values if applicable
        if majorVersion != nil && minorVersion != nil {
            httpVersionMajor = majorVersion!
            httpVersionMinor = minorVersion!
        }
    
    }
    
    
    /// Process our headers.
    ///
    /// a) there are some special case headers we want to deal with directly.
    /// b) we want to add HTTP_ headers to the header table after noralizing
    /// c) everything else just discard
    private func processHeader (_ name : String, value: String) {
        
        if name.caseInsensitiveCompare("REQUEST_METHOD") == .orderedSame {
            
            // The request method (GET/POST/etc)
            method = value
            
        } else if name.caseInsensitiveCompare("REQUEST_URI") == .orderedSame {
            
            // The URI as submitted to the web server
            requestUri = value
            
        } else if name.caseInsensitiveCompare("REMOTE_ADDR") == .orderedSame {
            
            // The actual IP address of the client
            remoteAddress = value
            
        } else if name.caseInsensitiveCompare("SERVER_PROTOCOL") == .orderedSame {
            
            // The HTTP protocol used by the client to speak with the
            // web server (HTTP/0.9, HTTP/1.0, HTTP/1.1, HTTP/2.0, etc)
            //
            processServerProtocol(value)
            
        }
        else if name.hasPrefix("HTTP_") {
            
            // Any other headers starting with "HTTP_", which are all
            // original headers sent from the browser.
            //
            // Note we return here to prevent these from potentially being
            // added a second time by the "add all headers" catch-all at the
            // end of this block.
            //
            processHttpHeader(name, value: value, remove: "HTTP_")
            return
            
        }

        // send all headers with FASTCGI_ prefixed.
        // this way we can see what's going on with them.
        //
        // Commented out for now pending community discussion as to best approach here
        
        /* headers.append("FASTCGI_".appending(name), value: value) */
        
    }
    
    /// process a record parsed from the connection.
    /// this has already been parsed and is just waiting for us to make a decision.
    private func processRecord (_ record : FastCGIRecordParser) throws {
        
        // is this record for a request that is an extra
        // request that we've already seen? if so, ignore it.
        //
        guard !extraRequestIds.contains(record.requestId) else {
            return
        }

        if status == Status.initial &&
            record.type == FastCGI.Constants.FCGI_BEGIN_REQUEST {
            
            // this is a request begin record and we haven't seen any requests
            // in this FastCGIServerRequest object. We're safe to begin parsing.
            //
            requestId = record.requestId
            status = Status.requestStarted
            
        }
        else if record.type == FastCGI.Constants.FCGI_BEGIN_REQUEST {
            
            // this is another request begin record and we've already received
            // one before now. this is a request to multiplex the connection or
            // is this a protocol error?
            //
            // if this is an extra begin request, we need to throw an error
            // and have the request 
            //
            if record.requestId == requestId {
                // a second begin request is insanity.
                //
                throw FastCGI.RecordErrors.protocolError
            } else {
                // this is an attempt to multiplex the connection. remember this
                // for later, as we can reject this safely with a response.
                //
                extraRequestIds.append(record.requestId)
            }
            
        }
        else if status == Status.requestStarted &&
            record.type == FastCGI.Constants.FCGI_PARAMS {
            
            // this is a parameter record
            
            // this request and the request in the record have to match
            // if not, the web server is still sending headers related to a 
            // multiplexing attempt.
            //
            // we want to keep processing the real request though, so we just 
            // ignore this for now and we can reject the attempt later.
            //
            guard record.requestId == requestId else {
                return
            }
            
            if record.headers.count > 0 {
                for pair in record.headers  {
                    // parse the header we've received
                    processHeader(pair["name"]!, value: pair["value"]!)
                }
            } else {
                // no params were received in this parameter record.
                // which means parameters are either completed (a blank param
                // record is sent to terminate parameter delivery) or the web
                // server is badly misconfigured. either way, attempt to 
                // process and we can reject this as an error state later
                // as necessary.
                //
                postProcessParameters()
                status = Status.headersComplete
            }
            
        }
        else if status == Status.headersComplete &&
            record.type == FastCGI.Constants.FCGI_STDIN {
            
            // Headers are complete and we're received STDIN records.
            
            // this request and the request in the record have to match
            // if not, the web server is still sending headers related to a
            // multiplexing attempt.
            //
            // we want to keep processing the real request though, so we just
            // ignore this for now and we can reject the attempt later.
            //
            guard record.requestId == requestId else {
                return
            }
            
            if let data = record.data, data.count > 0 {
                // we've received some request body data as part of the STDIN
                //
                bodyChunk.append(data: data)
            }
            else {
                // a zero length stdin means request is done
                //
                status = Status.requestComplete
            }
            
        }
        
    }
    
    /// Parse the request from FastCGI.
    func parse (_ callback: (FastCGIParserErrorType) -> Void) {
        
        
        var networkBuffer = Data()
        
        // we want to repeat this until we're done
        // in case the intake data isn't sufficient to
        // parse completed records.
        //
        repeat {
            
            do {
                var socketBuffer = Data()
                let bytesRead = try socket.read(into: &socketBuffer)
                
                guard bytesRead > 0 else {
                    // did our client disconnect? strange.
                    callback(.clientDisconnect)
                    return
                }
                
                // add the read data to our main buffer
                networkBuffer.append(socketBuffer)
                
                // we want to parse records out one at a time.
                repeat {
                    // make a parser
                    let parser = FastCGIRecordParser(networkBuffer)
                    
                    // replace our network buffer of read data with the 
                    // data sent back from the parser (data left over once the 
                    // record at the head of the array was parsed
                    // 
                    // Note that if we get an error indicating that the buffer 
                    // suffered an exhaustion, we want to read more data from 
                    // the socket as it's likely that we don't have sufficient
                    // data yet.
                    //
                    do {
                        let remainingData = try parser.parse()
                        
                        if remainingData == nil {
                            networkBuffer.count = 0
                        } else {
                            networkBuffer.count = 0
                            networkBuffer.append(remainingData!)
                        }
                    }
                    catch FastCGI.RecordErrors.bufferExhausted {
                        // break out of this repeat, which will start the 
                        // outer repeat loop again (read more data from the
                        // socket).
                        //
                        // this means there was insufficient data to parse
                        // a single record and we need more.
                        //
                        break
                    }
                    
                    // if we got here, we parsed a record.
                    try processRecord(parser)
                    
                    // if we're ready to send back a response, do so
                    if status == Status.requestComplete {
                        callback(.success)
                        return
                    }
                    
                }
                while true
                
                
            } catch FastCGI.RecordErrors.invalidVersion {
                callback(.protocolError)
                return
            } catch FastCGI.RecordErrors.protocolError {
                callback(.protocolError)
                return
            } catch FastCGI.RecordErrors.emptyParameters {
                callback(.protocolError)
                return
            } catch FastCGI.RecordErrors.invalidType {
                callback(.invalidType)
                return
            } catch FastCGI.RecordErrors.unsupportedRole {
                callback(.unsupportedRole)
                return
            } catch {
                callback(.internalError)
                return
            }
            
        } while true
        
    }
}
