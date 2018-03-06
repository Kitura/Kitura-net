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
    This class provides an implementation of a buffer that can be added to and taken from in chunks. Data is always added to the end of the buffer (using `BufferList.append(...)` and taken out of the buffer (using `BufferList.fill(...)`) from the beginning towards the end. The location indicating where the next chunk of data will be taken from is maintained, this location can then be reset to enable data to be taken out of the buffer from the beginning again.
 
    In the below example, we create an empty `BufferList` instance. You can then append data to your `BufferList` instance, in our case `writeBuffer`. We then make two seperate appends. When `writeBuffer` contains the data which you wish to write out you can use `BufferList.fill(...)` to write out the data from the buffer to your chosen location, which in this case is `finalArrayOfNumbers`.
 
    ### Usage Example: ###
    ````swift
    var writeBuffer = BufferList()
 
    let firstArrayOfNumbers: [UInt8] = [1,2,3,4]
 
    // Append a set of data to the 'writeBuffer' object
    writeBuffer.append(bytes: UnsafePointer<UInt8>(firstArrayOfNumbers),
                       length: MemoryLayout<UInt8>.size * firstArrayOfNumbers.count)
 
    // Number of bytes stored in the 'writeBuffer' object
    print(writeBuffer.count)
    // Prints "4"
 
    let secondArrayOfNumbers: [UInt8] = [5,6,7,8]
 
    // Append a second set of data to the 'writeBuffer' object
    writeBuffer.append(bytes: UnsafePointer<UInt8>(secondArrayOfNumbers),
                       length: MemoryLayout<UInt8>.size * secondArrayOfNumbers.count)
 
    print(writeBuffer.count)
    // Prints "8"

    let finalArrayOfNumbers: [UInt8] = [0,0,0,0,0,0,0,0,9,10]
 
    // Fill the destination buffer 'finalArrayOfNumbers' with the data from 'writeBuffer'
    let count = writeBuffer.fill(buffer: UnsafeMutableRawPointer(mutating: finalArrayOfNumbers)
                           .assumingMemoryBound(to: UInt8.self), length: ((MemoryLayout<UInt8>.size)
                           * finalArrayOfNumbers.count))
 
    print("count = \(count), buffer is = \(finalArrayOfNumbers)" )
    // Prints "count = 8, buffer is = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]"
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
     Get the number of bytes stored in the `BufferList`.
    */
    public var count: Int {
        return localData.length
    }
    
    /**
     Read the data from the `BufferList`.
    */
    public var data: Data {
        return Data(bytes: localData.bytes, count: localData.length)
    }
    
    /**
     Creates a `BufferList` instance to store bytes to be written.
     
     ### Usage Example: ###
     ````swift
     var writeBuffer = BufferList()
     ````
     
     - Returns: A `BufferList` instance.
     
     */
    public init() {}
    
    /**
     Append bytes to the buffer.
     
     ### Usage Example: ###
     ````swift
     var writeBuffer = BufferList()
     let firstArrayOfNumbers: [UInt8] = [1,2,3,4]
     writeBuffer.append(bytes: UnsafePointer<UInt8>(firstArrayOfNumbers),
                        length: MemoryLayout<UInt8>.size * firstArrayOfNumbers.count)
     ````
     
     - Parameter bytes: The pointer to the bytes.
     - Parameter length: The number of bytes to append.
     
     */
    public func append(bytes: UnsafePointer<UInt8>, length: Int) {
        localData.append(bytes, length: length)
    }
    

    /**
     Append data into the `BufferList`.
     
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
     Fill an array with data from the buffer. The data is copied from the BufferList to `array`.
     
     ### Usage Example: ###
     ````swift
     let count = writeBuffer.fill(array: [UInt8])
     ````
     
     - Parameter array: A [UInt8] for the data you want from the buffer.
     
     - Returns: The number of bytes copied from this `BufferList` to `array`. This will be the length of `array` or the number of bytes in the buffer, whichever is smaller.
     
     */
    public func fill(array: inout [UInt8]) -> Int {
        
        return fill(buffer: UnsafeMutablePointer(mutating: array), length: array.count)
    }
    
    /**
     Fill memory with data from a `BufferList`. The data is copied from the `BufferList` to `buffer`.
     
     ### Usage Example: ###
     ````swift
     let count = writeBuffer.fill(buffer: UnsafeMutableRawPointer(buf).assumingMemoryBound(to: UInt8.self), length: size)
     ````
     
     - Parameter buffer: A `NSMutablePointer` to the beginning of the memory to be filled.
     - Parameter length: The number of bytes to fill.
     
     - Returns: The number of bytes copied from this `BufferList` to `buffer`. This will be `length` or the number of bytes in this `BufferList`, whichever is smaller.
     
     */
    public func fill(buffer: UnsafeMutablePointer<UInt8>, length: Int) -> Int {
        
        let result = min(length, localData.length - byteIndex)
        let bytes = localData.bytes.assumingMemoryBound(to: UInt8.self) + byteIndex
        #if swift(>=4.1)
            UnsafeMutableRawPointer(buffer).copyMemory(from: bytes, byteCount: result)
        #else
            UnsafeMutableRawPointer(buffer).copyBytes(from: bytes, count: result)
        #endif
        byteIndex += result
        
        return result
        
    }

    /**
     Fill a `Data` structure with data from the buffer.
     
     ### Usage Example: ###
     ````swift
     let count = writeBuffer.fill(data: &data)
     ````
     
     - Parameter data: The `Data` structure to fill from the data in the buffer.
     
     - Returns: The number of bytes actually copied from the buffer.
     
     */
    public func fill(data: inout Data) -> Int {
        
        let result = localData.length - byteIndex
        data.append(localData.bytes.assumingMemoryBound(to: UInt8.self) + byteIndex, count: result)
        byteIndex += result
        return result
        
    }
    
    /**
     Fill a `NSMutableData` with data from the buffer.
     
     - Parameter data: The `NSMutableData` object to fill from the data in the buffer.
     
     - Returns: The number of bytes actually copied from the buffer.
     
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
     Reset the buffer to the beginning position and the buffer length to zero.
     
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
     Sets the buffer back to the beginning position. The next `BufferList.fill()` will take data from the beginning of the buffer.
     
     ### Usage Example: ###
     ````swift
     writeBuffer.rewind()
     ````
    */
    public func rewind() {
        
        byteIndex = 0
        
    }
    
}
