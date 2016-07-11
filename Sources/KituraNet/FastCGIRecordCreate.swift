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

class FastCGIRecordCreate {
    
    //
    // variables
    //
    var recordType : UInt8
    var recordSubType : UInt8
    var requestId : UInt16
    var data : NSData?
    
    // 
    // init for making a new record
    //
    init() {
        self.recordType = FastCGI.Constants.FCGI_NO_TYPE
        self.recordSubType = FastCGI.Constants.FCGI_SUBTYPE_NO_TYPE
        self.requestId = FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID
        self.data = nil
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
    
    //
    // Create the shared starting portion of a FastCGI,
    // shared by all FastCGI records we'll be generating
    //
    private func createRecordStarter() -> NSMutableData {
        let r = NSMutableData();
        
        var v : UInt8 = FastCGI.Constants.FASTCGI_PROTOCOL_VERSION
        var t : UInt8 = self.recordType
        var requestIdB1 : UInt8 = UInt8(self.requestId >> 8)
        var requestIdB0 : UInt8 = UInt8(self.requestId & 0x00ff)
        
        r.append(&v, length: 1);
        r.append(&t, length: 1);
        r.append(&requestIdB1, length: 1)
        r.append(&requestIdB0, length: 1)
        
        return r;
    }
    
    //
    // Generate an "END REQUEST" record of subtype "COMPLETE"
    //
    private func finalizeRequestCompleteRecord(data: NSMutableData) -> NSData {
        
        let contentLength : UInt16 = 8
        var contentLengthB1 : UInt8 = UInt8(contentLength >> 8)
        var contentLengthB0 : UInt8 = UInt8(contentLength & 0x00ff)
        var protocolStatus : UInt8 = self.recordSubType
        
        data.append(&contentLengthB1, length: 1)
        data.append(&contentLengthB0, length: 1)
        
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
    // Generate a data (STDOUT) record
    //
    private func finalizeDataRecord(data: NSMutableData) -> NSData {
        
        let contentData : NSData = self.data == nil ? NSData() : self.data!
        let contentLength : UInt16 = UInt16(contentData.length)
        var contentLengthB1 : UInt8 = UInt8(contentLength >> 8)
        var contentLengthB0 : UInt8 = UInt8(contentLength & 0x00ff)
        
        // note that we will align all of our data structures to 8 bytes
        var paddingLength : Int = Int(contentLength % 8)
        
        if (paddingLength > 0) {
            paddingLength = 8 - paddingLength
        }

        var paddingLengthB0 : UInt8 = UInt8(paddingLength)

        data.append(&contentLengthB1, length: 1)
        data.append(&contentLengthB0, length: 1)
        data.append(&paddingLengthB0, length: 1)
        
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
    // Note we limit to what we can generate for testing.
    //
    private func recordTest() throws -> Void {
        
        // check that our record type is ok
        //
        var recordTypeOk : Bool = false
        
        if (self.recordType == FastCGI.Constants.FCGI_END_REQUEST) {
            recordTypeOk = true
        } else if (self.recordType == FastCGI.Constants.FCGI_STDOUT) {
            recordTypeOk = true
        }
        
        guard recordTypeOk else {
            throw FastCGI.RecordErrors.InvalidType
        }
        
        // check that our subtype is ok, if applicable
        //
        if self.recordType == FastCGI.Constants.FCGI_END_REQUEST {
            
            var subRecordTypeOk : Bool = false
            
            if (self.recordSubType == FastCGI.Constants.FCGI_REQUEST_COMPLETE) {
                subRecordTypeOk = true
            }
            
            guard subRecordTypeOk else {
                throw FastCGI.RecordErrors.InvalidSubType
            }
            
        }
        
        // check that our request id is valid
        //
        guard self.requestId != FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID else {
            throw FastCGI.RecordErrors.InvalidRequestId
        }
        
        // check that our data object, if any, isn't larger than 16-bits worth of data
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
        
        if (self.recordType == FastCGI.Constants.FCGI_END_REQUEST) {
            return self.finalizeRequestCompleteRecord(data: record)
        }
        else if (self.recordType == FastCGI.Constants.FCGI_STDOUT) {
            return self.finalizeDataRecord(data: record)
        }
        else {
            // this will never happen as the recordTest() prevented it 
            // but it keeps the compiler from complaining.
            throw FastCGI.RecordErrors.InvalidType
        }
        
    }
    
}