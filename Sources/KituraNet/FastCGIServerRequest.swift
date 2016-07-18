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

import Foundation
import KituraSys
import Socket

public class FastCGIServerRequest : ServerRequest {
    
    ///
    /// Socket for the request
    ///
    private let socket: Socket
    
    ///
    /// server IP address pulled from socket
    ///
    public private(set) var remoteAddress: String = ""

    ///
    /// Major version for HTTP
    ///
    public private(set) var httpVersionMajor: UInt16? = 1
    
    ///
    /// Minor version for HTTP
    ///
    public private(set) var httpVersionMinor: UInt16? = 1
    
    ///
    /// Set of headers
    ///
    public var headers = HeadersContainer()
    
    ///
    /// HTTP Method
    ///
    public private(set) var method: String = ""
    
    ///
    /// URL strings.
    ///
    public var urlString : String {
        guard self.url.length > 0 else {
            return ""
        }
        return StringUtils.fromUtf8String(self.url)!
    }
    
    ///
    /// URL Components received from FastCGI
    ///
    private var requestScheme : String? = nil
    private var requestHost : String? = nil
    private var requestServerAddress : String? = nil
    private var requestServerName : String? = nil
    private var requestPort : String? = nil
    private var requestUri : String? = nil
    
    ///
    /// Raw URL
    ///
    public private(set) var url = NSMutableData()

    ///
    /// Chunk of body read in by the http_parser, filled by callbacks to onBody
    ///
    private var bodyChunk = BufferList()

    ///
    /// State of incoming message handling
    ///
    private var status = Status.initial
    
    ///
    /// The request ID established by the FastCGI client
    /// We also store an array of request ID's that are not our primary
    /// one. When the main request is done, the FastCGIServer can reject the
    /// extra requests as being unusable.
    ///
    public private(set) var requestId : UInt16 = 0
    public private(set) var extraRequestIds : [UInt16] = []
    
    ///
    /// Some defaults
    ///
    private static let defaultProtocolScheme : String = "http"
    private static let defaultHttpPorts : [String] = ["80", "443"]
    private static let defaultMethod : String = "GET"
    private static let defaultAddress : String = "127.0.0.1"
    
    ///
    /// List of status states
    ///
    private enum Status {
        case initial
        case requestStarted
        case headersComplete
        case requestComplete
    }
    
    ///
    /// HTTP parser error types
    ///
    public enum FastCGIParserErrorType {
        case success
        case protocolError
        case invalidType
        case clientDisconnect
        case unsupportedRole
        case internalError
    }
    
    ///
    /// Constructor
    ///
    required public init (socket: Socket) {
        self.socket = socket
    }
    
    // 
    // Read data received (perhaps from POST) into an NSData object
    //
    public func read(into data: NSMutableData) throws -> Int {
        return self.bodyChunk.fill(data: data)
    }
    
    //
    // Read all data into the object.
    //
    public func readAllData(into data: NSMutableData) throws -> Int {
        return self.bodyChunk.fill(data: data)
    }
    
    //
    // Read data received (perhaps from POST) as a string
    //
    public func readString() throws -> String? {
        let data : NSMutableData = NSMutableData()
        let bytes : Int = self.bodyChunk.fill(data: data)
        
        if bytes > 0 {
            return StringUtils.fromUtf8String(data)
        } else {
            return ""
        }
    }
    
    //
    // Now that parameter blocks have been received, scrub through them
    // in order to attempt to assemble a request URL from the data received.
    // 
    // This involves:
    // - The received request scheme (http/https)
    // - Determining the requested host from, in order:
    //      * The Host header, or...
    //      * The server name received from FastCGI, or...
    //      * The server IP address received from FastCGI, or...
    //      * A fail-over default (localhost)
    // - The port number the web browser connected to
    // - The original request URI
    //
    func postProcessUrlParameter() -> Void {
        
        // reset the current url
        //
        self.url.length = 0
        
        // set our protocol scheme
        //
        if self.requestScheme?.characters.count > 0 {
            
            // use the request scheme as received
            #if os(Linux)
                self.url.append(StringUtils.toUtf8String(self.requestScheme!)!)
            #else
                self.url.append(StringUtils.toUtf8String(self.requestScheme!)! as Data)
            #endif
            
        } else {
            
            // we received no request scheme - use the default
            #if os(Linux)
                self.url.append(StringUtils.toUtf8String(FastCGIServerRequest.defaultProtocolScheme)!)
            #else
                self.url.append(StringUtils.toUtf8String(FastCGIServerRequest.defaultProtocolScheme)! as Data)
            #endif
            
        }

        #if os(Linux)
            self.url.append(StringUtils.toUtf8String("://")!)
        #else
            self.url.append(StringUtils.toUtf8String("://")! as Data)
        #endif
        
        // set our host name
        //
        if self.requestHost?.characters.count > 0 {
            
            // use the requested host as received
            #if os(Linux)
                self.url.append(StringUtils.toUtf8String(self.requestHost!)!)
            #else
                self.url.append(StringUtils.toUtf8String(self.requestHost!)! as Data)
            #endif
            
        } else if self.requestServerName?.characters.count > 0 {
            
            // use the requested server name as received
            #if os(Linux)
                self.url.append(StringUtils.toUtf8String(self.requestServerName!)!)
            #else
                self.url.append(StringUtils.toUtf8String(self.requestServerName!)! as Data)
            #endif
            
        } else if self.requestServerAddress?.characters.count > 0 {
            
            // use the requested server address as received
            #if os(Linux)
                self.url.append(StringUtils.toUtf8String(self.requestServerAddress!)!)
            #else
                self.url.append(StringUtils.toUtf8String(self.requestServerAddress!)! as Data)
           #endif
            
        } else {
            
            // use a failover default as the server address
            #if os(Linux)
                self.url.append(StringUtils.toUtf8String(FastCGIServerRequest.defaultAddress)!)
            #else
                self.url.append(StringUtils.toUtf8String(FastCGIServerRequest.defaultAddress)! as Data)
            #endif
            
        }
        
        // set the port
        //
        if self.requestPort?.characters.count > 0 {
            
            // we received a port - we'll append it if it's not a standard
            // HTTP port that is typically used (80, 443)
            //
            if !FastCGIServerRequest.defaultHttpPorts.contains(self.requestPort!) {
                #if os(Linux)
                    self.url.append(StringUtils.toUtf8String(":")!)
                    self.url.append(StringUtils.toUtf8String(self.requestPort!)!)
                #else
                    self.url.append(StringUtils.toUtf8String(":")! as Data)
                    self.url.append(StringUtils.toUtf8String(self.requestPort!)! as Data)
                #endif
            }
        }
        
        // set the uri
        //
        if self.requestUri?.characters.count > 0 {
            
            // use the URI as received
            #if os(Linux)
                self.url.append(StringUtils.toUtf8String(self.requestUri!)!)
            #else
                self.url.append(StringUtils.toUtf8String(self.requestUri!)! as Data)
            #endif
            
        }
                
    }
    
    //
    // We've received all the parameters the server is going to send us, 
    // so lets massage these into place and make sure, at worst, sane 
    // defaults are in place.
    //
    private func postProcessParameters() {
        
        // make sure our method is set
        if self.method.characters.count == 0 {
            self.method = FastCGIServerRequest.defaultMethod
        }
        
        // make sure our remoteAddress is set
        if self.remoteAddress.characters.count == 0 {
            self.remoteAddress = self.socket.remoteHostname
        }
        
        // complete our URL string
        self.postProcessUrlParameter()
        
    }
    
    //
    // FastCGI delivers headers that were originally sent by the browser/client
    // with "HTTP_" prefixed. We want to normalize these out to remove HTTP_
    // and correct the capitilization (first letter of each word capitilized).
    //
    private func processHttpHeader(_ name: String, value: String, remove: String) {
        
        var processedName : String = name.substring(from:
            name.index(name.startIndex, offsetBy: remove.characters.count))
        
        processedName = processedName.replacingOccurrences(of: "_", with: "-")
        processedName = processedName.capitalized
        
        self.headers.append(processedName as String, value: value)
    }
    
    //
    // Parse the server protocol into a major and minor version
    //
    private func processServerProtocol(_ protocolString: String) {
        
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
            self.httpVersionMajor = majorVersion!
            self.httpVersionMinor = minorVersion!
        }
    
    }
    
    
    // process our headers.
    //
    // a) there are some special case headers we want to deal with directly.
    // b) we want to add HTTP_ headers to the header table after noralizing
    // c) everything else just discard
    //
    private func processHeader (_ name : String, value: String) {
        
        if name.caseInsensitiveCompare("REQUEST_METHOD") == .orderedSame {
            
            // The request method (GET/POST/etc)
            self.method = value
            
        } else if name.caseInsensitiveCompare("REQUEST_SCHEME") == .orderedSame {
            
            // The request scheme (HTTP or HTTPS)
            self.requestScheme = value
            
        } else if name.caseInsensitiveCompare("HTTP_HOST") == .orderedSame {
            
            // the "Host" header transmitted by the client
            //
            // Note we return here to prevent these from potentially being
            // added a second time by the "add all headers" catch-all at the
            // end of this block.
            //
            self.requestHost = value
            self.processHttpHeader(name, value: value, remove: "HTTP_")
            return
            
        } else if name.caseInsensitiveCompare("SERVER_ADDR") == .orderedSame {
            
            // The server address as specified by the web server
            self.requestServerAddress = value
            
        } else if name.caseInsensitiveCompare("SERVER_NAME") == .orderedSame {
            
            // The server name as specified by the web server.
            self.requestServerName = value
            
        } else if name.caseInsensitiveCompare("SERVER_PORT") == .orderedSame {
            
            // The port the original web server received the request on
            self.requestPort = value
            
        } else if name.caseInsensitiveCompare("REQUEST_URI") == .orderedSame {
            
            // The URI as submitted to the web server
            self.requestUri = value
            
        } else if name.caseInsensitiveCompare("REMOTE_ADDR") == .orderedSame {
            
            // The actual IP address of the client
            self.remoteAddress = value
            
        } else if name.caseInsensitiveCompare("SERVER_PROTOCOL") == .orderedSame {
            
            // The HTTP protocol used by the client to speak with the
            // web server (HTTP/1.0, HTTP/1.1, HTTP/2.0, etc)
            //
            self.processServerProtocol(value)
            
        }
        else if name.hasPrefix("HTTP_") {
            
            // Any other headers starting with "HTTP_", which are all
            // original headers sent from the browser.
            //
            // Note we return here to prevent these from potentially being
            // added a second time by the "add all headers" catch-all at the
            // end of this block.
            //
            self.processHttpHeader(name, value: value, remove: "HTTP_")
            return
            
        }

        // send all headers with FASTCGI_ prefixed.
        // this way we can see what's going on with them.
        //
        // Commented out for now pending community discussion as to best approach here
        
        /* self.headers.append("FASTCGI_".appending(name), value: value) */
        
    }
    
    // process a record parsed from the connection.
    // this has already been parsed and is just waiting for us to make a decision.
    //
    private func processRecord (_ record : FastCGIRecordParser) throws {
        
        // is this record for a request that is an extra
        // request that we've already seen? if so, ignore it.
        //
        guard !self.extraRequestIds.contains(record.requestId) else {
            return
        }

        if self.status == Status.initial &&
            record.type == FastCGI.Constants.FCGI_BEGIN_REQUEST {
            
            // this is a request begin record and we haven't seen any requests
            // in this FastCGIServerRequest object. We're safe to begin parsing.
            //
            self.requestId = record.requestId
            self.status = Status.requestStarted
            
        }
        else if record.type == FastCGI.Constants.FCGI_BEGIN_REQUEST {
            
            // this is another request begin record and we've already received
            // one before now. this is a request to multiplex the connection or
            // is this a protocol error?
            //
            // if this is an extra begin request, we need to throw an error
            // and have the request 
            //
            if record.requestId == self.requestId {
                // a second begin request is insanity.
                //
                throw FastCGI.RecordErrors.protocolError
            } else {
                // this is an attempt to multiplex the connection. remember this
                // for later, as we can reject this safely with a response.
                //
                self.extraRequestIds.append(record.requestId)
            }
            
        }
        else if self.status == Status.requestStarted &&
            record.type == FastCGI.Constants.FCGI_PARAMS {
            
            // this is a parameter record
            
            // this request and the request in the record have to match
            // if not, the web server is still sending headers related to a 
            // multiplexing attempt.
            //
            // we want to keep processing the real request though, so we just 
            // ignore this for now and we can reject the attempt later.
            //
            guard record.requestId == self.requestId else {
                return
            }
            
            if record.headers.count > 0 {
                for pair in record.headers  {
                    // parse the header we've received
                    self.processHeader(pair["name"]!, value: pair["value"]!)
                }
            } else {
                // no params were received in this parameter record.
                // which means parameters are either completed (a blank param
                // record is sent to terminate parameter delivery) or the web
                // server is badly misconfigured. either way, attempt to 
                // process and we can reject this as an error state later
                // as necessary.
                //
                self.postProcessParameters()
                self.status = Status.headersComplete
            }
            
        }
        else if self.status == Status.headersComplete &&
            record.type == FastCGI.Constants.FCGI_STDIN {
            
            // Headers are complete and we're received STDIN records.
            
            // this request and the request in the record have to match
            // if not, the web server is still sending headers related to a
            // multiplexing attempt.
            //
            // we want to keep processing the real request though, so we just
            // ignore this for now and we can reject the attempt later.
            //
            guard record.requestId == self.requestId else {
                return
            }
            
            if record.data?.length > 0 {
                // we've received some request body data as part of the STDIN
                //
                self.bodyChunk.append(data: record.data!)
            }
            else {
                // a zero length stdin means request is done
                //
                self.status = Status.requestComplete
            }
            
        }
        
    }
    
    //
    // Parse the request from FastCGI.
    //
    func parse (_ callback: (FastCGIParserErrorType) -> Void) {
        
        
        let networkBuffer : NSMutableData = NSMutableData()
        
        // we want to repeat this until we're done
        // in case the intake data isn't sufficient to
        // parse completed records.
        //
        repeat {
            
            do {
                let socketBuffer : NSMutableData = NSMutableData()
                let bytesRead = try socket.read(into: socketBuffer)
                
                guard bytesRead > 0 else {
                    // did our client disconnect? strange.
                    callback(.clientDisconnect)
                    return
                }
                
                // add the read data to our main buffer
                #if os(Linux)
                    networkBuffer.append(socketBuffer)
                #else
                    networkBuffer.append(socketBuffer as Data)
                #endif
                
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
                        let remainingData : NSData = try parser.parse()
                        #if os(Linux)
                            networkBuffer.setData(remainingData)
                        #else
                            networkBuffer.setData(remainingData as Data)
                        #endif
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
                    try self.processRecord(parser)
                    
                    // if we're ready to send back a response, do so
                    if self.status == Status.requestComplete {
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
