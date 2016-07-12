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

#if os(Linux)
    import Foundation
    import Glibc
#else
    import Darwin
    import Foundation
#endif

class FastCGIRecordCreate {
    
    //
    // variables
    //
    var recordType : UInt8
    var protocolStatus : UInt8
    var requestId : UInt16    
    var data : NSData?
    var requestRole : UInt16
    var keepAlive : Bool
    var params : [(String,String)] = []
    
    // 
    // init for making a new record
    //
    init() {
        self.recordType = FastCGI.Constants.FCGI_NO_TYPE
        self.protocolStatus = FastCGI.Constants.FCGI_SUBTYPE_NO_TYPE
        self.requestId = FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID
        self.data = nil
        self.requestRole = FastCGI.Constants.FCGI_NO_ROLE
        self.keepAlive = false
    }
    
    //
    // Write one or more zero bytes to a Data object
    //
    private func writeZero(data: NSMutableData, count: Int) {
        var zeroByte : UInt8 = 0
        for _ in 1...count {
            data.append(&zeroByte, length: 1)
        }
    }
    
    // Helper to turn UInt16 from local to network.
    //
    private static func networkByteOrderSmall(_ from: UInt16) -> UInt16 {
        #if os(Linux)
            return Glibc.htons(from)
        #else
            return CFSwapInt16HostToBig(from)
        #endif
    }
    
    // Helper to turn UInt32 from local to network.
    //
    private static func networkByteOrderLarge(_ from: UInt32) -> UInt32 {
        #if os(Linux)
            return Glibc.htonl(from)
        #else
            return CFSwapInt32HostToBig(from)
        #endif
    }
    
    //
    // Create the shared starting portion of a FastCGI,
    // shared by all FastCGI records we'll be generating
    //
    private func createRecordStarter() -> NSMutableData {
        let r = NSMutableData();
        
        var v : UInt8 = FastCGI.Constants.FASTCGI_PROTOCOL_VERSION
        var t : UInt8 = self.recordType
        var requestId : UInt16 = FastCGIRecordCreate.networkByteOrderSmall(self.requestId)
        
        r.append(&v, length: 1);
        r.append(&t, length: 1);
        r.append(&requestId, length: 2)
        
        return r;
    }
    
    //
    // Generate an "END REQUEST" record of subtype "COMPLETE"
    //
    private func finalizeRequestCompleteRecord(data: NSMutableData) -> NSData {
        
        var contentLength : UInt16 = FastCGIRecordCreate.networkByteOrderSmall(UInt16(8))
        var protocolStatus : UInt8 = self.protocolStatus
        
        // content length
        data.append(&contentLength, length: 2)
        
        // padding length
        writeZero(data: data, count: 1)
        
        // reserved space
        writeZero(data: data, count: 1)
        
        // application id - we don't use this
        writeZero(data: data, count: 4)
        
        // protocol status
        data.append(&protocolStatus, length: 1)

        // reserved space
        writeZero(data: data, count: 3)
        
        return data
    }
    
    //
    // Generate a "BEGIN REQUEST" record
    //
    private func finalizeRequestBeginRecord(data: NSMutableData) -> NSData {
        
        var contentLength : UInt16 = FastCGIRecordCreate.networkByteOrderSmall(8)
        var requestRole : UInt16 = FastCGIRecordCreate.networkByteOrderSmall(self.requestRole)
        var flags : UInt8 = self.keepAlive ? (0 | FastCGI.Constants.FCGI_KEEP_CONN) : 0
        
        // content length
        data.append(&contentLength, length: 2)
        
        // padding length
        writeZero(data: data, count: 1)
        
        // reserved space
        writeZero(data: data, count: 1)
        
        // request role
        data.append(&requestRole, length: 2)
        
        // flags
        data.append(&flags, length: 1)
        
        // reserved space
        writeZero(data: data, count: 5)
        
        return data
    }
    
    //
    // Write encoded length (8 bit or 4x8bit) for a param record
    //
    private func writeEncodedLength(length: Int, into: NSMutableData) {
        
        if (length > 127) {
            var encodedLength : UInt32 = FastCGIRecordCreate.networkByteOrderLarge(UInt32(length)) | ~0xffffff7f
            into.append(&encodedLength, length: 4)
        }
        else {
            var encodedLength : UInt8 = UInt8(length)
            into.append(&encodedLength, length: 1)
        }
        
    }
    
    //
    // Generate parameter records
    //
    private func createParameterRecords() -> NSData {
        
        let content : NSMutableData = NSMutableData()
        
        for (key, value) in self.params {

            // generate our key and value
            let keyData : NSData? = key.data(using: NSUTF8StringEncoding)
            let valueData : NSData? = value.data(using: NSUTF8StringEncoding)

            guard keyData != nil else {
                continue
            }
            
            guard valueData != nil else {
                continue
            }
            
            self.writeEncodedLength(length: keyData!.length, into: content)
            self.writeEncodedLength(length: valueData!.length, into: content)
            
            content.append(keyData!)
            content.append(valueData!)
            
        }
        
        return content;
    }
    
    //
    // Generate a parameters (PARAMS) record
    //
    private func finalizeParams(data: NSMutableData) -> NSData {
        self.data = self.createParameterRecords()
        return self.finalizeDataRecord(data: data)
    }
    
    //
    // Generate a data (STDOUT) record
    //
    private func finalizeDataRecord(data: NSMutableData) -> NSData {
        
        let contentData : NSData = self.data == nil ? NSData() : self.data!
        var contentLength : UInt16 = FastCGIRecordCreate.networkByteOrderSmall(UInt16(contentData.length))
        
        // note that we will align all of our data structures to 8 bytes
        var paddingLength : Int = Int(contentData.length % 8)
        
        if (paddingLength > 0) {
            paddingLength = 8 - paddingLength
        }

        var paddingLengthEncoded : UInt8 = UInt8(paddingLength)

        data.append(&contentLength, length: 2)
        data.append(&paddingLengthEncoded, length: 1)
        
        // reserved space
        self.writeZero(data: data, count: 1)
        // write our data block
        data.append(contentData)
        
        // write any padding
        if (paddingLength > 0) {
            self.writeZero(data: data, count: paddingLength)
        }
        
        return data
    }
    
    //
    // Test the internal record for sanity before generation
    //
    private func recordTest() throws -> Void {
        
        // check that our record type is ok
        //
        var recordTypeOk : Bool = false
        
        if (self.recordType == FastCGI.Constants.FCGI_END_REQUEST) {
            recordTypeOk = true
        } else if (self.recordType == FastCGI.Constants.FCGI_STDOUT) {
            recordTypeOk = true
        } else if (self.recordType == FastCGI.Constants.FCGI_STDIN) {
            recordTypeOk = true
        } else if (self.recordType == FastCGI.Constants.FCGI_PARAMS) {
            recordTypeOk = true
        } else if (self.recordType == FastCGI.Constants.FCGI_BEGIN_REQUEST) {
            recordTypeOk = true
        }
        
        guard recordTypeOk else {
            throw FastCGI.RecordErrors.InvalidType
        }
        
        // check that our subtype is ok, if applicable
        //
        if self.recordType == FastCGI.Constants.FCGI_END_REQUEST {
            
            var subRecordTypeOk : Bool = false
            
            if (self.protocolStatus == FastCGI.Constants.FCGI_REQUEST_COMPLETE) {
                subRecordTypeOk = true
            }
            else if (self.protocolStatus == FastCGI.Constants.FCGI_CANT_MPX_CONN) {
                subRecordTypeOk = true
            }
            else if (self.protocolStatus == FastCGI.Constants.FCGI_UNKNOWN_ROLE) {
                subRecordTypeOk = true
            }
            
            guard subRecordTypeOk else {
                throw FastCGI.RecordErrors.InvalidSubType
            }
            
        }
        else if self.recordType == FastCGI.Constants.FCGI_BEGIN_REQUEST {
            
            var roleOk : Bool = false
            
            // we only support one role right now
            if self.requestRole == FastCGI.Constants.FCGI_RESPONDER {
                roleOk = true
            }
            
            guard roleOk else {
                throw FastCGI.RecordErrors.InvalidRole
            }
            
        }
        else if self.recordType == FastCGI.Constants.FCGI_PARAMS {
            
            guard self.params.count > 0 else {
                throw FastCGI.RecordErrors.EmptyParams
            }
            
        }
        
        // check that our request id is valid
        //
        guard self.requestId != FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID else {
            throw FastCGI.RecordErrors.InvalidRequestId
        }
        
        // check that our data object, if any, isn't larger 
        // than 16-bits addressable worth of data
        //
        if (self.data != nil) {
            guard self.data!.length <= 65535 else {
                throw FastCGI.RecordErrors.OversizeData
            }
        }
        
    }
        
    //
    // Generate the record currently contained by the class
    //
    func create() throws -> NSData {
        
        // rely on throw to abort if there is an issue
        try recordTest();
        
        let record : NSMutableData = self.createRecordStarter()
        
        if self.recordType == FastCGI.Constants.FCGI_BEGIN_REQUEST {
            return self.finalizeRequestBeginRecord(data: record)
        }
        else if self.recordType == FastCGI.Constants.FCGI_END_REQUEST {
            return self.finalizeRequestCompleteRecord(data: record)
        }
        else if self.recordType == FastCGI.Constants.FCGI_PARAMS {
            return self.finalizeParams(data: record)
        }
        else if self.recordType == FastCGI.Constants.FCGI_STDOUT || self.recordType == FastCGI.Constants.FCGI_STDIN {
            return self.finalizeDataRecord(data: record)
        }
        else {
            // this will never happen as the recordTest() prevented it 
            // but it keeps the compiler from complaining.
            throw FastCGI.RecordErrors.InvalidType
        }
        
    }
    
}