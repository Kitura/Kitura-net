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
    private var errorFlag = false
    
    private var inputNotAvailable = true
    private let waitingForInput: dispatch_semaphore_t
    private let readBufferLock: dispatch_semaphore_t
    private var socketNotClosed = true
    
    private let buffer = NSMutableData()
    
    var remoteHostname: String { return clientSocket.remoteHostname }
    
    init(clientSocket: Socket) {
        self.clientSocket = clientSocket
        
        waitingForInput = dispatch_semaphore_create(0)
        readBufferLock = dispatch_semaphore_create(1)
    }
    
    func addToAvailableData(from: NSData) {
        let needToLock = buffer.length != 0
        if  needToLock {
            dispatch_semaphore_wait(readBufferLock, DISPATCH_TIME_FOREVER)
        }
        
        buffer.append(from)
        
        if  inputNotAvailable  {
            dispatch_semaphore_signal(waitingForInput)
            inputNotAvailable = false
        }
        if  needToLock  {
            dispatch_semaphore_signal(readBufferLock)
        }
    }
    
    func readSynchronously(into: NSMutableData) -> Int {
        if  inputNotAvailable  {
            dispatch_semaphore_wait(waitingForInput, DISPATCH_TIME_FOREVER)
        }
        let result: Int
        if  buffer.length != 0  {
            dispatch_semaphore_wait(readBufferLock, DISPATCH_TIME_FOREVER)
            if  errorFlag  {
                result = -1
            }
            else {
                result = buffer.length
                into.append(buffer)
            }
            buffer.length = 0
            inputNotAvailable = socketNotClosed
            dispatch_semaphore_signal(readBufferLock)
        }
        else {
            result = 0
        }
        
        return result
    }
}