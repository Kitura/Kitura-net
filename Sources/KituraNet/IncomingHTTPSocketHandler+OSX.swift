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

#if os(OSX) || os(iOS) || os(tvOS) || os(watchOS)

import Dispatch
import Foundation


import LoggerAPI
import Socket

extension IncomingHTTPSocketHandler {
    
    
    ///
    /// Perform platform specfic setup, invoked by the init function
    ///
    func setup() {
        channel = DispatchIO(type: .stream, fileDescriptor: socket.socketfd, queue: HTTPServer.clientHandlerQueue.osQueue) { error in
            self.socket.close()
            self.inProgress = false
            self.keepAliveUntil = 0.0
        }
        channel!.setLimit(lowWater: 1)
    
        let bufferLength = 16 * 1024
        
        channel!.read(offset: 0, length: bufferLength, queue: HTTPServer.clientHandlerQueue.osQueue) {done, data, error in
            self.handleRead(done: done, data: data, error: error)
        }
    }
    
    private func handleRead(done: Bool, data: DispatchData?, error: Int32) {
        guard !done else {
            if error != 0 {
                Log.error("Error reading from \(socket.socketfd)")
                print("Error reading from \(socket.socketfd)")
            }
            close()
            return
        }
        
        guard let data = data else { return }
        
        let dataBuffer = NSMutableData()
        _ = data.enumerateBytes() { (buffer: UnsafeBufferPointer<UInt8>, byteIndex: Int, stop: inout Bool) in
            guard  let address = buffer.baseAddress  else {
                stop = true
                return
            }
            dataBuffer.append(address+byteIndex, length: buffer.count-byteIndex)
        }
        process(dataBuffer)
    }
    
    
    
    ///
    /// Write data to the socket
    ///
    func write(from: NSData) {
        let buffer = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(from.bytes), count: from.length)
        let data = DispatchData(bytes: buffer)
        
        channel!.write(offset: 0, data: data, queue: HTTPServer.clientHandlerQueue.osQueue) { _,_,_ in }
    }
    
    ///
    /// Close the socket
    ///
    func close() {
        channel!.close()
    }
    
    
}

#endif
