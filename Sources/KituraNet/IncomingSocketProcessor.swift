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
/**
This protocol defines the API of the classes used to process the data that comes in from a client's request. There should be one `IncomingSocketProcessor` instance per incoming request.
### Usage Example: ###
````swift
 var processor: IncomingSocketProcessor?
````
*/
public protocol IncomingSocketProcessor: class {
    
    /**
     The socket if idle will be kep alive until...
    ### Usage Example: ###
    ````swift
    processor?.keepAliveUntil = 0.0
    ````
    */
    var keepAliveUntil: TimeInterval { get set }
    
    /**
    A flag to indicate that the socket has a request in progress
    ### Usage Example: ###
    ````swift
    processor?.inProgress = false
    ````
    */
    var inProgress: Bool { get set }

    /**
    A back reference to the `IncomingSocketHandler` processing the socket that this `IncomingDataProcessor` is processing.
    ### Usage Example: ###
    ````swift
    processor?.handler = nil
    ````
    */
    weak var handler: IncomingSocketHandler? { get set }

    /// Process data read from the socket.
    ///
    /// - Parameter buffer: An NSData object containing the data that was read in
    ///                    and needs to be processed.
    ///
    /// - Returns: true if the data was processed, false if it needs to be processed later.
    func process(_ buffer: NSData) -> Bool
    
    /// Write data to the socket
    ///
    /// - Parameter from: An NSData object containing the bytes to be written to the socket.
    func write(from data: NSData)
    
    /// Write a sequence of bytes in an array to the socket
    ///
    /// - Parameter from: An UnsafeRawPointer to the sequence of bytes to be written to the socket.
    /// - Parameter length: The number of bytes to write to the socket.
    func write(from bytes: UnsafeRawPointer, length: Int)
    
    /**
    Close the socket and mark this handler as no longer in progress.
    ### Usage Example: ###
    ````swift
    processor?.close()
    ````
    */
    func close()
    
    /**
    Called by the `IncomingSocketHandler` to tell the `IncomingSocketProcessor` that the socket has been closed by the remote side.
    ### Usage Example: ###
    ````swift
    processor?.socketClosed()
    ````
    */
    func socketClosed()
}
