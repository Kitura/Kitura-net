/*
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of athe License at
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

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

class FastCGIRecordCreate {
    
    //
    // Variables
    //
    var recordType : UInt8 = FastCGI.Constants.FCGI_NO_TYPE
    var protocolStatus : UInt8 = FastCGI.Constants.FCGI_SUBTYPE_NO_TYPE
    var requestId : UInt16 = FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID
    var data : Data?
    var requestRole : UInt16 = FastCGI.Constants.FCGI_NO_ROLE
    var keepAlive : Bool = false
    var parameters : [(String,String)] = []
    
    //
    // Append one or more zero bytes to the provided NSMutableData object
    //
    private func appendZeroes(data: inout Data, count: Int) {
        var zeroByte : UInt8 = 0
        for _ in 1...count {
            data.append(&zeroByte, count: 1)
        }
    }
    
    //
    // Helper to turn UInt16 from local byte order to network byte order,
    // which is typically Little to Big.
    //
    private static func getNetworkByteOrderSmall(from localOrderedBytes: UInt16) -> UInt16 {
        #if os(Linux)
            return Glibc.htons(localOrderedBytes)
        #else
            return CFSwapInt16HostToBig(localOrderedBytes)
        #endif
    }
    
    //
    // Helper to turn UInt32 from local byte order to network byte order,
    // which is typically Little to Big.
    //
    private static func getNetworkByteOrderLarge(from localOrderedBytes: UInt32) -> UInt32 {
        #if os(Linux)
            return Glibc.htonl(localOrderedBytes)
        #else
            return CFSwapInt32HostToBig(localOrderedBytes)
        #endif
    }
    
    // A helper method to append various types to a Data object
    private func appendBytes(to: inout Data, bytes: UnsafeRawPointer, count: Int) {
        to.append(UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self), count: count)
    }
    
    //
    // Create the shared starting portion of a FastCGI,
    // shared by all FastCGI records we'll be generating
    //
    private func createRecordStarter() -> Data {
        var r = Data()
        
        var v : UInt8 = FastCGI.Constants.FASTCGI_PROTOCOL_VERSION
        var t : UInt8 = recordType
        var requestId : UInt16 = FastCGIRecordCreate.getNetworkByteOrderSmall(from: self.requestId)
        
        r.append(&v, count: 1)
        r.append(&t, count: 1)
        appendBytes(to: &r, bytes: &requestId, count: 2)
        
        return r
    }
    
    //
    // Generate an "END REQUEST" record of subtype "COMPLETE"
    //
    private func finalizeRequestCompleteRecord(data: inout Data) -> Data {
        
        var contentLength : UInt16 = FastCGIRecordCreate.getNetworkByteOrderSmall(from: UInt16(8))
        var protocolStatus : UInt8 = self.protocolStatus
        
        // content length
        appendBytes(to: &data, bytes: &contentLength, count: 2)
        
        // padding length
        appendZeroes(data: &data, count: 1)
        
        // reserved space
        appendZeroes(data: &data, count: 1)
        
        // application id - we don't use this
        appendZeroes(data: &data, count: 4)
        
        // protocol status
        appendBytes(to: &data, bytes: &protocolStatus, count: 1)

        // reserved space
        appendZeroes(data: &data, count: 3)
        
        return data
    }
    
    //
    // Generate a "BEGIN REQUEST" record
    //
    private func finalizeRequestBeginRecord(data: inout Data) -> Data {
        
        var contentLength : UInt16 = FastCGIRecordCreate.getNetworkByteOrderSmall(from: 8)
        var requestRole : UInt16 = FastCGIRecordCreate.getNetworkByteOrderSmall(from: self.requestRole)
        var flags : UInt8 = keepAlive ? FastCGI.Constants.FCGI_KEEP_CONN : 0
        
        // content length
        appendBytes(to: &data, bytes: &contentLength, count: 2)
        
        // padding length
        appendZeroes(data: &data, count: 1)
        
        // reserved space
        appendZeroes(data: &data, count: 1)
        
        // request role
        appendBytes(to: &data, bytes: &requestRole, count: 2)
        
        // flags
        data.append(&flags, count: 1)
        
        // reserved space
        appendZeroes(data: &data, count: 5)
        
        return data
    }
    
    //
    // Write encoded length (8 bit or 4x8bit) for a param record
    //
    private func writeEncodedLength(length: Int, into: inout Data) {
        
        if length > 127 {
            var encodedLength : UInt32 = FastCGIRecordCreate.getNetworkByteOrderLarge(from: UInt32(length)) | ~0xffffff7f
            appendBytes(to: &into, bytes: &encodedLength, count: 4)
        }
        else {
            var encodedLength : UInt8 = UInt8(length)
            into.append(&encodedLength, count: 1)
        }
        
    }
    
    //
    // Generate parameter records
    //
    private func createParameterRecords() -> Data {
        
        var content = Data()
        
        for (key, value) in parameters {

            // generate our key and value by converting to 
            // Data from String using UTF-8.
            //
            guard let keyData = key.data(using: .utf8) else {
                // this key couldn't be copied as data, skip the parameter
                continue
            }
            
            guard let valueData = value.data(using: .utf8)  else {
                // this key couldn't be copied as data, skip the parameter
                continue
            }
            
            writeEncodedLength(length: keyData.count, into: &content)
            writeEncodedLength(length: valueData.count, into: &content)
            
            content.append(keyData)
            content.append(valueData)
        }
        
        return content
    }
    
    //
    // Generate a parameters (PARAMS) record
    //
    private func finalizeParameters(data: inout Data) -> Data {
        self.data = createParameterRecords()
        return finalizeDataRecord(data: &data)
    }
    
    //
    // Generate a data (STDOUT) record
    //
    private func finalizeDataRecord(data: inout Data) -> Data {
        
        let contentData = self.data == nil ? Data() : self.data!
        var contentLength : UInt16 = FastCGIRecordCreate.getNetworkByteOrderSmall(from: UInt16(contentData.count))
        
        // note that we will align all of our data structures to 8 bytes
        var paddingLength : Int = Int(contentData.count % 8)
        
        if paddingLength > 0 {
            paddingLength = 8 - paddingLength
        }

        var paddingLengthEncoded : UInt8 = UInt8(paddingLength)

        appendBytes(to: &data, bytes: &contentLength, count: 2)
        data.append(&paddingLengthEncoded, count: 1)
        
        // reserved space
        appendZeroes(data: &data, count: 1)
        // write our data block
        data.append(contentData)
        
        // write any padding
        if paddingLength > 0 {
            appendZeroes(data: &data, count: paddingLength)
        }
        
        return data
    }
    
    //
    // Test the internal record for sanity before generation
    //
    private func recordTest() throws -> Void {
        
        // check that our record type is ok
        //
        switch recordType {
        case FastCGI.Constants.FCGI_END_REQUEST,
             FastCGI.Constants.FCGI_STDOUT,
             FastCGI.Constants.FCGI_STDIN,
             FastCGI.Constants.FCGI_PARAMS,
             FastCGI.Constants.FCGI_BEGIN_REQUEST:
            break
            
        default:
            throw FastCGI.RecordErrors.invalidType
        }
        
        // check that our subtype is ok, if applicable
        //
        if recordType == FastCGI.Constants.FCGI_END_REQUEST {
            
            switch protocolStatus {
            case FastCGI.Constants.FCGI_REQUEST_COMPLETE,
                 FastCGI.Constants.FCGI_CANT_MPX_CONN,
                 FastCGI.Constants.FCGI_UNKNOWN_ROLE:
                break
                
            default:
                throw FastCGI.RecordErrors.invalidSubType
            }
            
        }
        else if recordType == FastCGI.Constants.FCGI_BEGIN_REQUEST {
            
            guard requestRole == FastCGI.Constants.FCGI_RESPONDER else {
                throw FastCGI.RecordErrors.invalidRole
            }
            
        }
        
        // check that our request id is valid
        //
        guard requestId != FastCGI.Constants.FASTCGI_DEFAULT_REQUEST_ID else {
            throw FastCGI.RecordErrors.invalidRequestId
        }
        
        // check that our data object, if any, isn't larger 
        // than 16-bits addressable worth of data
        //
        guard let data = data else {
            return
        }
        guard data.count <= 65535 else {
            throw FastCGI.RecordErrors.oversizeData
        }
        
    }
        
    //
    // Generate the record currently contained by the class
    //
    func create() throws -> Data {
        
        // rely on throw to abort if there is an issue
        try recordTest()
        
        var record = createRecordStarter()
        
        switch recordType {
        case FastCGI.Constants.FCGI_BEGIN_REQUEST:
            return finalizeRequestBeginRecord(data: &record)
            
        case FastCGI.Constants.FCGI_END_REQUEST:
            return finalizeRequestCompleteRecord(data: &record)
            
        case FastCGI.Constants.FCGI_PARAMS:
            return finalizeParameters(data: &record)
            
        default:
            // either STDIN or STDOUT
            return finalizeDataRecord(data: &record)
        }
        
    }
    
}
