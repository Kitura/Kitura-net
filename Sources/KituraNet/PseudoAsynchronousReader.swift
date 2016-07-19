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

import Dispatch
import Foundation

import LoggerAPI
import Socket

class PseudoAsynchronousReader {

    private let clientSocket: Socket
    
    private var inputNotAvailable = true
    
    #if os(Linux)
        private let waitingForInput: dispatch_semaphore_t
        private let readBufferLock: dispatch_semaphore_t
    #else
        private let waitingForInput = DispatchSemaphore(value: 0)
        private let readBufferLock = DispatchSemaphore(value: 1)
    #endif
    
    private let buffer = NSMutableData()
    
    var remoteHostname: String { return clientSocket.remoteHostname }
    
    init(clientSocket: Socket) {
        self.clientSocket = clientSocket
        
        #if os(Linux)
            waitingForInput = dispatch_semaphore_create(0)
            readBufferLock = dispatch_semaphore_create(1)
        #endif
    }
    
    func addToAvailableData(from: NSData) {
        let needToLock = buffer.length != 0
        if  needToLock {
            #if os(Linux)
                dispatch_semaphore_wait(readBufferLock, DISPATCH_TIME_FOREVER)
            #else
                _ = readBufferLock.wait(timeout: DispatchTime.distantFuture)
            #endif
        }
        
        #if os(Linux)
            buffer.append(from)
        #else
            buffer.append(from as Data)
        #endif
        
        if  inputNotAvailable  {
            #if os(Linux)
                dispatch_semaphore_signal(waitingForInput)
            #else
                waitingForInput.signal()
            #endif
            inputNotAvailable = false
        }
        if  needToLock  {
            #if os(Linux)
                dispatch_semaphore_signal(readBufferLock)
            #else
                readBufferLock.signal()
            #endif
        }
    }
    
    func readSynchronously(into: NSMutableData) -> Int {
        if  inputNotAvailable  {
            #if os(Linux)
                dispatch_semaphore_wait(waitingForInput, DISPATCH_TIME_FOREVER)
            #else
                _ = waitingForInput.wait(timeout: DispatchTime.distantFuture)
            #endif
        }
        let result: Int
        if  buffer.length != 0  {
            #if os(Linux)
                dispatch_semaphore_wait(readBufferLock, DISPATCH_TIME_FOREVER)
            #else
                _ = readBufferLock.wait(timeout: DispatchTime.distantFuture)
            #endif
            result = buffer.length
            #if os(Linux)
                into.append(buffer)
            #else
                into.append(buffer as Data)
            #endif
            buffer.length = 0
            inputNotAvailable = true
            #if os(Linux)
                dispatch_semaphore_signal(readBufferLock)
            #else
                readBufferLock.signal()
            #endif
        }
        else {
            result = 0
        }
        
        return result
    }
}
