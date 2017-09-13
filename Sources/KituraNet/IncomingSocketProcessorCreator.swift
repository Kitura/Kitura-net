/*
 * Copyright IBM Corporation 2017
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

import Socket

/// Implementations of the `IncomingSocketProcessorCreator` protocol create
/// an implementation of the `IncomingSocketProcessor` protocol to process
/// the data from a new incoming socket.
public protocol IncomingSocketProcessorCreator {
    var name: String { get }
    
    /// Create an instance of the  `IncomingSocketProcessor`s for use with new incoming sockets.
    ///
    /// - Parameter socket: The new incoming socket.
    /// - Parameter using: The `ServerDelegate` the HTTPServer is working with, which should be used
    ///                   by the created `IncomingSocketProcessor`, if it works with `ServerDelegate`s.
    func createIncomingSocketProcessor(socket: Socket, using: ServerDelegate) -> IncomingSocketProcessor
}
