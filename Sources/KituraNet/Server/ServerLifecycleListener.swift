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

/// A class that is used for storing callbacks and performing them.
class ServerLifecycleListener {

    typealias ErrorClosure = (Swift.Error) -> Void

    /// Callbacks that should be performed when server starts.
    private var startCallbacks = [() -> Void]()

    /// Callbacks that should be performed when server stops.
    private var stopCallbacks = [() -> Void]()

    /// Callbacks that should be performed when server throws an error.
    private var failCallbacks = [ErrorClosure]()

    /// Callbacks that should be performed when listenSocket.acceptClientConnection throws an error.
    private var clientConnectionFailCallbacks = [ErrorClosure]()

    /// Perform all `start` callbacks.
    ///
    /// Performs all `start` callbacks.
    func performStartCallbacks() {
        for callback in self.startCallbacks {
            callback()
        }
    }

    /// Perform all `stop` callbacks.
    ///
    /// Performs all `stop` callbacks.
    func performStopCallbacks() {
        for callback in self.stopCallbacks {
            callback()
        }
    }

    /// Perform all `fail` callbacks.
    ///
    /// Performs all `fail` callbacks.
    ///
    /// - Parameter error: An error that should be processed by callbacks.
    func performFailCallbacks(with error: Swift.Error) {
        for callback in self.failCallbacks {
            callback(error)
        }
    }

    /// Performs all `clientConnectionFail` callbacks.
    ///
    /// - Parameter error: An error that should be processed by callbacks.
    func performClientConnectionFailCallbacks(with error: Swift.Error) {
        for callback in self.clientConnectionFailCallbacks {
            callback(error)
        }
    }

    /// Add `start` callback. And perform it immediately if needed.
    ///
    /// - Parameter perform: The value indicating should callback be performed immediately or not.
    /// - Parameter callback: A callback that will be stored for `start` listener.
    func addStartCallback(perform: Bool = false, _ callback: @escaping () -> Void) {
        if perform {
            callback()
        }
        self.startCallbacks.append(callback)
    }

    /// Add `stop` callback. And perform it immediately if needed.
    ///
    /// - Parameter perform: The value indicating should callback be performed immediately or not.
    /// - Parameter callback: A callback that will be stored for `stop` listener.
    func addStopCallback(perform: Bool = false, _ callback: @escaping () -> Void) {
        if perform {
            callback()
        }
        self.stopCallbacks.append(callback)
    }

    /// Add `fail` callback. And perform it immediately if needed.
    ///
    /// - Parameter callback: A callback that will be stored for `fail` listener.
    func addFailCallback(_ callback: @escaping (Swift.Error) -> Void) {
        self.failCallbacks.append(callback)
    }

    /// Add `clientConnectionFail` callback. And perform it immediately if needed.
    ///
    /// - Parameter callback: A callback that will be stored for `clientConnectionFail` listener.
    func addClientConnectionFailCallback(_ callback: @escaping (Swift.Error) -> Void) {
        self.clientConnectionFailCallbacks.append(callback)
    }
}
