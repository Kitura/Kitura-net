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

import Dispatch

/// A class that provides a set of helper functions that enables a caller to wait
/// for a group of listener blocks to finish executing.
public class ListenerGroup {
    
    /// Group for waiting on listeners
    private static let group = DispatchGroup()

    /// Wait for all of the listeners to stop
    public static func waitForListeners() {
        _ = group.wait(timeout: DispatchTime.distantFuture)
    }
    
    /// Enqueue a block of code on a given queue, assigning
    /// it to the listener group in the process (so we can wait
    /// on it later).
    ///
    /// - Parameter on: The queue on to which the provided block will be enqueued
    ///                for asynchronous execution.
    /// - Parameter block: The block to be enqueued for asynchronous execution.
    public static func enqueueAsynchronously(on queue: DispatchQueue, block: DispatchWorkItem) {
        queue.async(group: ListenerGroup.group, execute: block)
    }
    
}
