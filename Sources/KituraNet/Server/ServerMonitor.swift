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


/// A protocol for implementing a delegate to receive monitoring events from KituraNet.
public protocol ServerMonitor {
    /// An event fired when a HTTP request has finished being parsed and is about
    /// to be passed to the `ServerDelegate` for processing.
    ///
    /// - Parameter request: The `ServerRequest` class instance for the request starting.
    /// - Parameter response: The `ServerResponse` class instance for the request starting.
    func started(request: ServerRequest, response: ServerResponse)
    
    /// An event fired when the processing of a HTTP request has finished.
    ///
    /// - Parameter request: The `ServerRequest` class instance for the request that finished.
    /// - Parameter response: The `ServerResponse` class instance for the request  that finished.
    func finished(request: ServerRequest?, response: ServerResponse)
}

/// A struct that holds the reference to the server wide monitoring delegate.
public struct Monitor {
    /// The reference to the server wide monitoring delegate.
    public static var delegate: ServerMonitor?
}
