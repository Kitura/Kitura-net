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
    private static let quietPorts : [String] = ["80", "443"]
    private static let defaultMethod : String = "GET"
    private static let defaultAddress : String = "127.0.0.1"
    private static let defaultUri : String = "/"
    
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
        
        if (bytes>0) {
            return StringUtils.fromUtf8String(data)
        } else {
            return ""
        }
    }
    
    func postProcessUrlParameter() -> Void {
        
        // reset the current url
        self.url.length = 0
        
        // set our protocol scheme
        if (self.requestScheme?.characters.count > 0) {
            self.url.append(StringUtils.toUtf8String(self.requestScheme!)!)
        } else {
            self.url.append(StringUtils.toUtf8String(FastCGIServerRequest.defaultProtocolScheme)!)
        }

        self.url.append(StringUtils.toUtf8String("://")!)
        
        // set our host name
        if (self.requestHost?.characters.count > 0) {
            self.url.append(StringUtils.toUtf8String(self.requestHost!)!)
        } else if (self.requestServerName?.characters.count > 0) {
            self.url.append(StringUtils.toUtf8String(self.requestServerName!)!)
        } else if (self.requestServerAddress?.characters.count > 0) {
            self.url.append(StringUtils.toUtf8String(self.requestServerAddress!)!)
        } else {
            self.url.append(StringUtils.toUtf8String(FastCGIServerRequest.defaultAddress)!)
        }
        
        // set the port
        if (self.requestPort?.characters.count > 0) {
            if (!FastCGIServerRequest.quietPorts.contains(self.requestPort!)) {
                self.url.append(StringUtils.toUtf8String(":")!)
                self.url.append(StringUtils.toUtf8String(self.requestPort!)!)
            }
        }
        
        // set the uri
        if (self.requestUri?.characters.count > 0) {
            self.url.append(StringUtils.toUtf8String(self.requestUri!)!)
        }
                
    }
    
    //
    // We've received all the parameters the server is going to send us, 
    // so lets massage these into place and make sure, at worst, sane 
    // defaults are in place.
    //
    private func postProcessParameters() {
        
        // make sure our method is set
        if (self.method.characters.count == 0) {
            self.method = FastCGIServerRequest.defaultMethod
        }
        
        // make sure our remoteAddress is set
        if (self.remoteAddress.characters.count == 0) {
            self.remoteAddress = self.socket.remoteHostname
        }
        
        // complete our URL string
        self.postProcessUrlParameter()
        
        // make sure our protocol is configured
        
    }
    
    //
    // FastCGI delivers headers that were originally sent by the browser/client
    // with "HTTP_" prefixed.
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
            return;
        }
        
        let versionPortion : String = protocolString.substring(from:
            protocolString.index(protocolString.startIndex, offsetBy: "http/".characters.count))
        var decimalPosition : Int = 0
        
        for i in versionPortion.characters {
            if i == "." {
                break;
            } else {
                decimalPosition = decimalPosition + 1
            }
        }
        
        var majorVersion : UInt16? = nil
        var minorVersion : UInt16? = nil
        
        // get major version
        if (decimalPosition > 0) {
            let majorPortion : String = versionPortion.substring(to:
                versionPortion.index(versionPortion.startIndex, offsetBy: decimalPosition))
            majorVersion = UInt16(majorPortion)
        }
        
        // get minor version
        if (protocolString.characters.count > decimalPosition) {
            let minorPortion : String = versionPortion.substring(from:
                versionPortion.index(versionPortion.startIndex, offsetBy: decimalPosition + 1))
            minorVersion = UInt16(minorPortion)
        }
        
        // assign our values if applicable
        if (majorVersion != nil && minorVersion != nil) {
            self.httpVersionMajor = majorVersion!
            self.httpVersionMinor = minorVersion!
        }
    
    }
    
    
    // process our headers.
    // there are some special case headers we want to deal with directly.
    // for the rest else, we want to add HTTP_ headers to the header table
    // after formatting to Web style (remove HTTP_, case and dash fixing, etc).
    // everything else we just discard.
    //
    private func processHeader (_ name : String, value: String) {
        
        if (name.caseInsensitiveCompare("REQUEST_METHOD") == .orderedSame) {
            self.method = value
        } else if (name.caseInsensitiveCompare("REQUEST_SCHEME") == .orderedSame) {
            self.requestScheme = value
        } else if (name.caseInsensitiveCompare("HTTP_HOST") == .orderedSame) {
            self.requestHost = value
            self.processHttpHeader(name, value: value, remove: "HTTP_")
        } else if (name.caseInsensitiveCompare("SERVER_ADDR") == .orderedSame) {
            self.requestServerAddress = value
        } else if (name.caseInsensitiveCompare("SERVER_NAME") == .orderedSame) {
            self.requestServerName = value
        } else if (name.caseInsensitiveCompare("SERVER_PORT") == .orderedSame) {
            self.requestPort = value
        } else if (name.caseInsensitiveCompare("REQUEST_URI") == .orderedSame) {
            self.requestUri = value
        } else if (name.caseInsensitiveCompare("REMOTE_ADDR") == .orderedSame) {
            self.remoteAddress = value
        } else if (name.caseInsensitiveCompare("SERVER_PROTOCOL") == .orderedSame) {
            self.processServerProtocol(value)
        }
        else if (name.hasPrefix("HTTP_")) {
            // this is where we process
            self.processHttpHeader(name, value: value, remove: "HTTP_")
            return;
        }

        // send all headers with FASTCGI_ prefixed.
        // this way we can see what's going on with them.
        // commented out for now pending community discussion as to best approach here
        
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
            return;
        }

        if (self.status == Status.initial && record.type == FastCGI.Constants.FCGI_BEGIN_REQUEST) {
            self.requestId = record.requestId
            self.status = Status.requestStarted
        }
        else if (record.type == FastCGI.Constants.FCGI_BEGIN_REQUEST) {
            self.extraRequestIds.append(record.requestId)
        }
        else if (self.status == Status.requestStarted && record.type == FastCGI.Constants.FCGI_PARAMS) {
            
            // this request and the request in the record have to match
            // if not, something utterly insane has happened (params without begin)
            // we want to keep processing the real request though, so we just ignore this
            guard record.requestId == self.requestId else {
                return;
            }
            
            if (record.headers.count > 0) {
                for pair in record.headers  {
                    // right here we can send to a proper processor
                    // this is where actual real transposition will happen 
                    // adn we can remove requestComplete() from the parse loop
                    self.processHeader(pair["name"]!, value: pair["value"]!)
                }
            } else {
                // no params were received in this parameter block.
                // which means parameters are completed.
                self.postProcessParameters()
                self.status = Status.headersComplete
            }
            
        }
        else if (self.status == Status.headersComplete && record.type == FastCGI.Constants.FCGI_STDIN) {
            
            // this request and the request in the record have to match
            // if not, something utterly insane has happened (params without begin)
            // we want to keep processing the real request though, so we just ignore this
            guard record.requestId == self.requestId else {
                return;
            }
            
            if (record.data!.length > 0) {
                // we've received some body data
                self.bodyChunk.append(data: record.data!)
            }
            else {
                // zero lenght stdin means request is done
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
        // in case the intaken data isn't sufficient to 
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
                        let remainingData : NSData = try parser.parse()
                        networkBuffer.setData(remainingData)
                    }
                    catch (FastCGI.RecordErrors.BufferExhausted) {
                        // break out of this repeat, which will loop
                        // us back to the top
                        break;
                    }
                    
                    // if we got here, we parsed a record.
                    try self.processRecord(parser)
                    
                    // if we're ready to send back a response, go ahead and do so
                    if (self.status == Status.requestComplete) {
                        callback(.success)
                        return;
                    }
                    
                }
                while true
                
                
            } catch (FastCGI.RecordErrors.InvalidVersion) {
                callback(.protocolError)
                return
            } catch (FastCGI.RecordErrors.InvalidType) {
                callback(.invalidType)
                return;
            } catch (FastCGI.RecordErrors.UnsupportedRole) {
                callback(.unsupportedRole)
                return;
            } catch {
                callback(.internalError)
                return;
            }
            
        } while true
        
    }
}