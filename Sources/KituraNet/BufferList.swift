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

// MARK: BufferList 

    /**
    This class provides an implementation of a buffer that can be added to and "taken" from in chunks. Data is always added to the end of the buffer and data is "taken" from the buffer from the beginning towards the end. A pointer is maintained as where the next chunk of data will be "taken" from. This pointer can be reset, to enable the data in the buffer to be fetched from the beginning again.
 
    ### Usage Example: ###
    ````swift
    //Create a BufferList object.
    var writeBuffer = BufferList()
 
    //Array of UInt8 to act as the buffer.
    let arrayOfNumbers: [UInt8] = [1,2,3,4]
 
    //Create a new constant of type Int of the number of bytes copied from the buffer.
    let count = writeBuffer.fill(buffer: UnsafeMutableRawPointer(mutating: arrayOfNumbers).assumingMemoryBound(to: UInt8.self), length: ((MemoryLayout<UInt8>.size) * 10))
 
    //Append some data to the initialized writeBuffer object.
    writeBuffer.append(bytes: UnsafePointer<UInt8>(bitPattern: 10)!, length: MemoryLayout<UInt8>.size)
    ````
    */

public class BufferList {

    // MARK: -- Private 
    
    /**
     Internal storage buffer
    */
    private let localData = NSMutableData(capacity: 4096) ?? NSMutableData()
    
    /**
     Byte offset inside of internal storage buffer
    */
    private var byteIndex = 0
    
    // MARK: Public
    
    /**
     Get the number of bytes stored in the BufferList.
    */
    public var count: Int {
        return localData.length
    }
    
    /**
     Read the data in the BufferList.
    */
    public var data: Data {
        return Data(bytes: localData.bytes, count: localData.length)
    }
    
    /**
     Creates a BufferList instance to store bytes to be written.
     
     ### Usage Example: ###
     ````swift
     var writeBuffers = BufferList()
     ````
     
     - Returns: A BufferList instance.
     
     */
    public init() {}
    
    /**
     Append bytes to the buffer.
     
     ### Usage Example: ###
     ````swift
     writeBuffer.append(bytes + written, length: length - written)
     ````
     
     - Parameter bytes: The pointer to the bytes.
     - Parameter length: The number of bytes to append.
     
     */
    public func append(bytes: UnsafePointer<UInt8>, length: Int) {
        localData.append(bytes, length: length)
    }
    

    /**
     Append data into the BufferList.
     
     ### Usage Example: ###
     ````swift
     writeBuffer.append(data)
     ````
     
     - Parameter data: The data to append.
     
     */
    public func append(data: Data) {
        localData.append(data)
    }
    

    /**
     Fill an array with data from the buffer.
     
     ### Usage Example: ###
     ````swift
     let count = writeBuffer.fill(array: [UInt8])
     ````
     
     - Parameter array: A [UInt8] for the data you want from the buffer.
     
     - Returns: The number of bytes actually copied from the buffer. It will be the lesser of the number of bytes left in the buffer and the length of the array.
     
     */
    public func fill(array: inout [UInt8]) -> Int {
        
        return fill(buffer: UnsafeMutablePointer(mutating: array), length: array.count)
    }
    
    /**
     Fill memory with data from the buffer.
     
     ### Usage Example: ###
     ````swift
     let count = writeBuffer.fill(buffer: UnsafeMutableRawPointer(buf).assumingMemoryBound(to: UInt8.self), length: size)
     ````
     
     - Parameter buffer: A NSMutablePointer to the beginning of the memory to be filled.
     - Parameter length: The number of bytes to fill.
     
     - Returns: The number of bytes actually copied from the buffer. It will be the lesser of the number of bytes left in the buffer and the length of the memory area provided.
     
     */
    public func fill(buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Int {
        
        let result = min(length, localData.length - byteIndex)
        let bytes = localData.bytes.assumingMemoryBound(to: UInt8.self) + byteIndex
        UnsafeMutableRawPointer(buffer).copyBytes(from: bytes, count: result)
        byteIndex += result
        
        return result
        
    }

    /**
     Fill a Data Structure with data from the buffer.
     
     ### Usage Example: ###
     ````swift
     let count = writeBuffer.fill(data: &data)
     ````
     
     - Parameter data: The Data Structure to fill from the data in the buffer.
     
     - Returns: The number of bytes actually copied from the buffer. It will be equal to the number of bytes left in the buffer.
     
     */
    public func fill(data: inout Data) -> Int {
        
        let result = localData.length - byteIndex
        data.append(localData.bytes.assumingMemoryBound(to: UInt8.self) + byteIndex, count: result)
        byteIndex += result
        return result
        
    }
    
    /**
     Fill a NSMutableData with data from the buffer.
     
     - Parameter data: The NSMutableData object to fill from the data in the buffer.
     
     - Returns: The number of bytes actually copied from the buffer. It will be equal to the number of bytes left in the buffer.
     
     ### Usage Example: ###
     ````swift
     let count = writeBuffer.fill(data: &data)
     ````
     */
    public func fill(data: NSMutableData) -> Int {
        
        let result = localData.length - byteIndex
        data.append(localData.bytes.assumingMemoryBound(to: UInt8.self) + byteIndex, length: result)
        byteIndex += result
        return result
        
    }
    
    /**
     Resets the buffer to zero length and the beginning position.
     
     ### Usage Example: ###
     ````swift
     writeBuffer.reset()
     ````
    */
    public func reset() {
        
        localData.length = 0
        byteIndex = 0
        
    }
    
    /**
     Sets the buffer back to the beginning position. The next fill call will take data from the beginning of the buffer.
     
     ### Usage Example: ###
     ````swift
     writeBuffer.rewind()
     ````
    */
    public func rewind() {
        
        byteIndex = 0
        
    }
    
}
