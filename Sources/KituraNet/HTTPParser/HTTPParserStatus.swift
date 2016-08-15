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

/// List of parser states
enum HTTPParserState {
    
    case initial
    case headersComplete
    case messageComplete
    case reset
    
}

/// HTTP parser error types
enum HTTPParserErrorType {
    
    case parsedLessThanRead
    case unexpectedEOF
    case internalError // TODO
    
}

struct HTTPParserStatus {
    
    init() {}
    
    var state = HTTPParserState.initial
    var error: HTTPParserErrorType? = nil
    var keepAlive = false
    
    mutating func reset() {
        state = HTTPParserState.initial
        error = nil
        keepAlive = false
    }
}
