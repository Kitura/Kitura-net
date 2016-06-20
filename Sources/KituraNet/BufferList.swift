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

#if os(OSX)
    import Darwin
#elseif os(Linux)
    import Glibc
#endif

import Foundation

// MARK: BufferList 

public class BufferList {

    // MARK: -- Private 
    
    ///
    /// Internal storage buffer
    ///
    
    private var localData = NSMutableData(capacity: 4096)
    ///
    /// Byte offset inside of internal storage buffer
    private var byteIndex = 0
    
    // MARK: -- Public 
    
    ///
    /// Get the number of bytes stored in the BufferList
    public var count: Int {
        return localData!.length
    }
    
    ///
    /// Read the data in the BufferList
    ///
    public var data: NSData? {
        return localData as NSData?
    }
    
    ///
    /// Initializes a BufferList instance
    ///
    /// - Returns: a BufferList instance
    ///
    public init() {}
    
    /// 
    /// Append bytes in an array to buffer 
    ///
    /// Parameter bytes: a pointer to the array
    /// Parameter length: number of bytes in the array
    ///
    public func append(bytes: UnsafePointer<UInt8>, length: Int) {
        localData!.append(bytes, length: length)
    }
    
    ///
    /// Append data into BufferList 
    /// 
    /// Parameter data: The data to append
    ///
    public func append(data: NSData) {
        localData!.append(data.bytes, length: data.length)
    }
    
    ///
    /// Fill the buffer with a byte array data
    ///
    /// - Parameter buffer: a [UInt8] for data you want in the buffer
    ///
    /// - Returns:
    ///
    public func fill(array: inout [UInt8]) -> Int {
        
        let result = min(array.count, localData!.length-byteIndex)
        memcpy(UnsafeMutablePointer<UInt8>(array), localData!.bytes+byteIndex, Int(result))
        byteIndex += result
        
        return result
        
    }
    
    ///
    /// Fill the buffer with a byte array data
    ///
    /// - Parameter buffer: NSMutablePointer to the beginning of the array
    /// - Parameter length: the number of bytes in the array
    ///
    /// - Returns:
    ///
    public func fill(buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Int {
        
        let result = min(length, localData!.length-byteIndex)
        memcpy(buffer, localData!.bytes+byteIndex, Int(result))
        byteIndex += result
        
        return result
        
    }
    
    ///
    /// Fill the buffer with data 
    ///
    /// - Parameter data: NSMutableData you want in the buffer
    ///
    /// - Returns: 
    ///
    public func fill(data: NSMutableData) -> Int {
        
        let result = localData!.length-byteIndex
        data.append(localData!.bytes+byteIndex, length: result)
        byteIndex += result
        return result
        
    }
    
    ///
    /// Resets the buffer to zero length and the beginning position
    ///
    public func reset() {
        
        localData!.length = 0
        byteIndex = 0
        
    }
    
    ///
    /// Sets the buffer back to the beginning position
    ///
    public func rewind() {
        
        byteIndex = 0
        
    }
    
}
