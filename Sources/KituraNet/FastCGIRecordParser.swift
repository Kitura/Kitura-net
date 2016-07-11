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

class FastCGIRecordParser {
    
    // Variables
    //
    var version : UInt8 = 0
    var type : UInt8 = 0
    var requestId : UInt16 = 0
    var role : UInt16 = 0
    var flags : UInt8 = 0
    var headers : [Dictionary] = Array<Dictionary<String,String>>()
    var data : NSData? = nil
    var appStatus : UInt32 = 0
    var protocolStatus : UInt8 = 0
    
    var keepalive : Bool {
        return self.flags & FastCGI.Constants.FCGI_KEEP_CONN == 0 ? false : true
    }
    
    // Internal Variables
    //
    private var contentLength : UInt16 = 0
    private var paddingLength : UInt8 = 0
    private var pointer : Int = 0
    private var buffer : NSData
    private var bufferBytes : UnsafePointer<UInt8>
    
    // Pointer
    //
    func advance() throws -> Int {
        
        guard self.pointer < self.buffer.length else {
            throw FastCGI.RecordErrors.BufferExhausted
        }
        
        let r = self.pointer
        self.pointer = self.pointer + 1
        return r
    }
    
    func skip(_ count: Int) throws {
        self.pointer = self.pointer + count
        
        // because we're skipping, it's ok to be pointer=length because we 
        // may never be reading again. but pointer=(length+x) is bad (where x>0)
        // because it means there aren't the bytes we expected
        //
        guard self.pointer <= self.buffer.length else {
            throw FastCGI.RecordErrors.BufferExhausted
        }
    }
    
    // Initialize
    //
    init(_ data: NSData) {
        self.buffer = data
        self.bufferBytes = UnsafePointer<UInt8>(data.bytes)
    }
    
    //
    // Internal Functions
    //
    
    //
    // Parse FastCGI Version
    //
    private func parseVersion() throws {
        self.version = self.bufferBytes[try advance()]
        
        guard self.version == FastCGI.Constants.FASTCGI_PROTOCOL_VERSION else {
            throw FastCGI.RecordErrors.InvalidVersion
        }
    }
    
    // Parse record type.
    //
    private func parseType() throws {
        
        self.type = self.bufferBytes[try advance()]
        
        var typeOk : Bool = false
        
        switch (self.type) {
        case FastCGI.Constants.FCGI_BEGIN_REQUEST:
            typeOk = true;
            break;
        case FastCGI.Constants.FCGI_END_REQUEST:
            typeOk = true;
            break;
        case FastCGI.Constants.FCGI_PARAMS:
            typeOk = true;
            break;
        case FastCGI.Constants.FCGI_STDIN:
            typeOk = true;
            break;
        case FastCGI.Constants.FCGI_STDOUT:
            typeOk = true;
            break;
        default:
            typeOk = false;
            break;
        }
        
        guard typeOk else {
            throw FastCGI.RecordErrors.InvalidType
        }
        
    }
    
    // Parse request ID
    //
    private func parseRequestId() throws {
        
        let requestIdBytes1 = self.bufferBytes[try advance()]
        let requestIdBytes0 = self.bufferBytes[try advance()]
        let requestIdBytes : [UInt8] = [ requestIdBytes0, requestIdBytes1 ]
        
        self.requestId = UnsafePointer<UInt16>(requestIdBytes).pointee

    }

    // Parse content length.
    //
    private func parseContentLength() throws {
        
        let contentLengthBytes1 = self.bufferBytes[try advance()]
        let contentLengthBytes0 = self.bufferBytes[try advance()]
        let contentLengthBytes : [UInt8] = [ contentLengthBytes0, contentLengthBytes1 ]
        
        self.contentLength = UnsafePointer<UInt16>(contentLengthBytes).pointee
        
    }
    
    // Parse padding length
    //
    private func parsePaddingLength() throws {
        self.paddingLength = self.bufferBytes[try advance()]
    }

    // Parse a role
    //
    private func parseRole() throws {
        
        let roleByte1 = self.bufferBytes[try advance()]
        let roleByte0 = self.bufferBytes[try advance()]
        let roleBytes : [UInt8] = [ roleByte0, roleByte1 ]
        
        self.role = UnsafePointer<UInt16>(roleBytes).pointee
        self.flags = self.bufferBytes[try advance()]

        guard self.role == FastCGI.Constants.FCGI_RESPONDER else {
            throw FastCGI.RecordErrors.UnsupportedRole
        }
        
    }
    
    // Parse an app status
    //
    private func parseAppStatus() throws {
        
        let appStatusByte3 = self.bufferBytes[try advance()]
        let appStatusByte2 = self.bufferBytes[try advance()]
        let appStatusByte1 = self.bufferBytes[try advance()]
        let appStatusByte0 = self.bufferBytes[try advance()]
        let appStatusBytes : [UInt8] = [ appStatusByte0, appStatusByte1, appStatusByte2, appStatusByte3 ]
        
        self.appStatus = UnsafePointer<UInt32>(appStatusBytes).pointee
        
    }
    
    // Parse a protocol status
    //
    private func parseProtocolStatus() throws {
        self.protocolStatus = self.bufferBytes[try advance()]
    }
    
    // Parse raw data from a data record
    //
    private func parseData() throws {
        if (self.contentLength > 0) {
            self.data = NSData(bytes: self.bufferBytes+pointer, length: Int(self.contentLength))
            try skip(Int(self.contentLength))
        } else {
            self.data = NSData()
        }
    }
    
    //
    // The following functions parse the parameter blocks.
    // Because parameter blocks can be encoded sequentially
    // in a single record this is more complex than simply 
    // extracting blocks from a single record - hance the 
    // extra functions involved.
    //
    
    //
    // The parameter name/value length encoding scheme used by FastCGI
    // is interesting. Basically, it lets 1 byte be used to encode lengths
    // less than 127 bytes, but allocates 4 bytes to encode the length
    // of anything larger. We determine what state we're in by checking
    // the higher order bit of the first byte in the length. off = 127 or less,
    // on = 128 or larger.
    //
    // If we are using 4 bytes for a length value, we need to mask
    // that first byte with 0x7f when assembling it back into a 32-bit length
    // value.
    //
    //
    private func parseParameterLength() throws -> Int {
        
        
        let lengthPeek : UInt8 = self.bufferBytes[try advance()]
        
        if (lengthPeek >> 7 == 0) {
            return Int(lengthPeek)
        } else {
            let lengthByteB3 : UInt8 = lengthPeek
            let lengthByteB2 : UInt8 = self.bufferBytes[try advance()]
            let lengthByteB1 : UInt8 = self.bufferBytes[try advance()]
            let lengthByteB0 : UInt8 = self.bufferBytes[try advance()]
            let lengthBytes : [UInt8] = [ lengthByteB0, lengthByteB1, lengthByteB2, lengthByteB3 & 0x7f ]

            return Int(UnsafePointer<UInt32>(lengthBytes).pointee)
        }
        
    }
    
    // Parse a parameter block
    //
    private func parseParams() throws {
        
        guard self.contentLength > 0 else {
            return;
        }
        
        var contentRemaining : Int = Int(self.contentLength)
        
        repeat {
            let initialPointer : Int = self.pointer
            let nameLength : Int = try self.parseParameterLength()
            let valueLength : Int = try self.parseParameterLength()
            var nameString : String!
            var valueString : String!
            
            // capture a name if needed
            if (nameLength > 0) {
                let currentPointer : Int = pointer
                try skip(nameLength)
                let nameData = NSData(bytes: self.bufferBytes+currentPointer, length: nameLength)
                nameString = NSString(data: nameData, encoding: NSUTF8StringEncoding)!.bridge()
            } else {
                nameString = ""
            }
            
            // capture a value if needed
            if (valueLength > 0) {
                let currentPointer : Int = pointer
                try skip(valueLength)
                let valueData = NSData(bytes: self.bufferBytes+currentPointer, length: valueLength)
                valueString = NSString(data: valueData, encoding: NSUTF8StringEncoding)!.bridge()
            } else {
                valueString = ""
            }
            
            // all good - store it
            self.headers.append(["name": nameString!, "value": valueString!])
            
            // adjust our position
            contentRemaining = contentRemaining - (self.pointer - initialPointer)
            
        }
        while (contentRemaining > 0)
        
    }
    
    // Skip any padding indicated, then return the unused portion
    // of our data buffer. We're done reading this record.
    //
    private func skipPaddingThenReturn() throws -> NSMutableData {
        
        if (self.paddingLength > 0) {
            try skip(Int(self.paddingLength))
        }
        
        let remainingBufferBytes = self.buffer.length - self.pointer
        
        if (remainingBufferBytes == 0) {
            return NSMutableData()
        } else {
            return NSMutableData(bytes: buffer.bytes+self.pointer, length: remainingBufferBytes)
        }
        
    }
    
    // Parser the data, return any extra
    //
    func parse() throws -> NSMutableData {
        
        // make parser go now!        
        try parseVersion()
        try parseType()
        try parseRequestId()
        try parseContentLength()
        try parsePaddingLength()
        try skip(1)
        
        if (self.type == FastCGI.Constants.FCGI_BEGIN_REQUEST) {
            try parseRole()
            try skip(5)
        } else if (self.type == FastCGI.Constants.FCGI_END_REQUEST) {
            try parseAppStatus()
            try parseProtocolStatus()
            try skip(3)
        } else if (self.type == FastCGI.Constants.FCGI_PARAMS) {
            try parseParams()
        } else if (self.type == FastCGI.Constants.FCGI_STDIN) {
            try parseData()
        } else if (self.type == FastCGI.Constants.FCGI_STDOUT) {
            try parseData()
        }
        
        // return new data object representing any data
        // not part of the parsed record
        return try skipPaddingThenReturn()
    }
    
    
}