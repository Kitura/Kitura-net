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

/// The "root" class for the FastCGI server implementation.
public class FastCGI {
 
    //
    // Global Constants used through FastCGI protocol implementation
    //
    struct Constants {
        
        // general
        //
        static let FASTCGI_PROTOCOL_VERSION : UInt8 = 1
        static let FASTCGI_DEFAULT_REQUEST_ID : UInt16 = 0
        
        // FastCGI record types
        //
        static let FCGI_NO_TYPE : UInt8 = 0
        static let FCGI_BEGIN_REQUEST : UInt8 = 1
        static let FCGI_END_REQUEST : UInt8 = 3
        static let FCGI_PARAMS : UInt8 = 4
        static let FCGI_STDIN : UInt8 = 5
        static let FCGI_STDOUT : UInt8 = 6
        
        // sub types
        //
        static let FCGI_SUBTYPE_NO_TYPE : UInt8 = 99
        static let FCGI_REQUEST_COMPLETE : UInt8 = 0
        static let FCGI_CANT_MPX_CONN : UInt8 = 1
        static let FCGI_UNKNOWN_ROLE : UInt8 = 3
        
        // roles
        //
        static let FCGI_NO_ROLE : UInt16 = 99
        static let FCGI_RESPONDER : UInt16 = 1
        
        // flags
        //
        static let FCGI_KEEP_CONN : UInt8 = 1
        
        // request headers of note
        // we translate these into internal variables
        //
        static let HEADER_REQUEST_METHOD : String = "REQUEST_METHOD";
        static let HEADER_REQUEST_SCHEME : String = "REQUEST_SCHEME";
        static let HEADER_HTTP_HOST : String = "HTTP_HOST";
        static let HEADER_REQUEST_URI : String = "REQUEST_URI";
    }
    
    //
    // Exceptions
    //
    enum RecordErrors : Swift.Error {
        
        case invalidType
        case invalidSubType
        case invalidRequestId
        case invalidRole
        case oversizeData
        case invalidVersion
        case emptyParameters
        case bufferExhausted
        case unsupportedRole
        case internalError
        case protocolError
    }

    /// Create a `FastCGIServer` instance.
    /// Provided as a convenience and for consistency
    /// with the HTTP implementation.
    ///
    /// - Returns: A `FastCGIServer` instance.
    public static func createServer() -> FastCGIServer {
        return FastCGIServer()
    }

    
}
