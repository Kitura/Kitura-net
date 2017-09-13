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

public enum KeepAliveState {
    
    case disabled
    case unlimited
    case limited(maxRequests: UInt)
    
    /// Returns true if there are requests remaining, or unlimited requests are allowed
    func keepAlive() -> Bool {
        switch self {
        case .unlimited: return true
        case .disabled: return false
        case .limited(let limit): return limit > 0
        }
    }
    
    /// Decrements the number of requests remaining
    mutating func decrement() -> Void {
        switch self {
        case .unlimited: break
        case .limited(let limit):
            assert(limit > 0, "Cannot decrement with zero requests remaining")
            self = .limited(maxRequests: limit - 1)
        case .disabled:
            assertionFailure("Cannot decrement when Keep-Alive is disabled")
        }
    }
    
    /// Returns the number of requests remaining if the KeepAlive state is `limited`.
    var requestsRemaining: UInt? {
        switch self {
        case .limited(let limit): return limit
        default: return nil
        }
    }
}
