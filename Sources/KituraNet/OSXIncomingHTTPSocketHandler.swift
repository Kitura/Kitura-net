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
        channel = dispatch_io_create(DISPATCH_IO_STREAM, socket.socketfd, HTTPServer.clientHandlerQueue.osQueue) { error in
            self.socket.close()
            self.inProgress = false
            self.keepAliveUntil = 0.0
        }
        dispatch_io_set_low_water(channel!, 1)
        
        dispatch_io_read(channel!, 0, Int.max, HTTPServer.clientHandlerQueue.osQueue) {done, data, error in
            self.handleRead(done: done, data: data, error: error)
        }
    }
    
    private func handleRead(done: Bool, data: dispatch_data_t?, error: Int32) {
        guard !done else {
            if error != 0 {
                Log.error("Error reading from \(socket.socketfd)")
                print("Error reading from \(socket.socketfd)")
            }
            close()
            return
        }
        
        guard let data = data else { return }
        
        let buffer = NSMutableData()
        let _ = dispatch_data_apply(data) { (region, offset, dataBuffer, size) -> Bool in
            guard let dataBuffer = dataBuffer else { return true }
            buffer.append(dataBuffer, length: size)
            return true
        }
        
        process(buffer)
    }
    
    
    
    ///
    /// Write data to the socket
    ///
    func write(from: NSData) {
        let temp = dispatch_data_create( from.bytes, from.length, HTTPServer.clientHandlerQueue.osQueue, nil)
        #if os(Linux)
            let data = temp
        #else
            guard let data = temp  else { return }
        #endif
        dispatch_io_write(channel!, 0, data, HTTPServer.clientHandlerQueue.osQueue) { _,_,_ in }
    }
    
    ///
    /// Close the socket
    ///
    func close() {
        dispatch_io_close(channel!, 0)
    }
    
    
}

#endif