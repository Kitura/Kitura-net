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

import XCTest

@testable import KituraNet

import Foundation

// Just enough of an IncomingSocketProcessor to make the tests work
class TestIncomingSocketProcessor: IncomingSocketProcessor {
    public weak var handler: IncomingSocketHandler?
    public var keepAliveUntil: TimeInterval = 0.0
    public var inProgress = true
    
    public func process(_ buffer: NSData) -> Bool {
        return true
    }
    
    public func write(from data: NSData) {
        handler?.write(from: data)
    }
    
    public func write(from bytes: UnsafeRawPointer, length: Int) {
        handler?.write(from: bytes, length: length)
    }
    
    public func close() {
        handler?.prepareToClose()
    }
    
    public func socketClosed() {}
}
