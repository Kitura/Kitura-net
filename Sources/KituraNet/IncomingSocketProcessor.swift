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

/// This protocol defines the API of the classes used to process the data that
/// comes in from a client's request. There should be one IncomingDataProcessor
/// per incoming request or not.
public protocol IncomingSocketProcessor: class {
    
    /// The socket if idle will be kep alive until...
    var keepAliveUntil: TimeInterval { get set }
    
    /// A flag to indicate that the socket has a request in progress
    var inProgress: Bool { get set }

    /// A back reference to the IncomingSocketHandler processing the socket that
    /// this IncomingDataProcessor is processing.    
    weak var handler: IncomingSocketHandler? { get set }

    /// Process data read from the socket. It is either passed to the HTTP parser or
    /// it is saved in the Pseudo synchronous reader to be read later on.
    func process(_ buffer: NSData)
    
    /// Write data to the socket
    func write(from data: Data)
    
    /// Close the socket and mark this handler as no longer in progress.
    func close()
}
