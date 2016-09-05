/*
 * Copyright IBM Corporation 2015
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

import LoggerAPI

public class HeadersContainer {
    
    /// The header storage
    internal var headers: [String: [String]] = [:]
    
    /// The map of case insensitive header fields to their actual names
    private var caseInsensitiveMap: [String: String] = [:]
    
    public subscript(key: String) -> [String]? {
        get {
            return get(key)
        }
        
        set(newValue) {
            if let newValue = newValue {
                set(key, value: newValue)
            }
            else {
                remove(key)
            }
        }
    }
    
    /// Append values to the header
    ///
    /// - Parameter key: the key
    /// - Parameter value: the value
    public func append(_ key: String, value: [String]) {
        
        let lowerCaseKey = key.lowercased()
        
        // Determine how to handle the header (append or merge)
        switch(lowerCaseKey) {
            
        // Headers with an array value (can appear multiple times, but can't be merged)
        case "set-cookie":
            if let headerKey = caseInsensitiveMap[lowerCaseKey] {
                headers[headerKey]? += value
            } else {
                set(key, lowerCaseKey: lowerCaseKey, value: value)
            }
            
        // Headers with a simple value that are not merged (i.e. duplicates dropped)
        // https://dxr.mozilla.org/mozilla/source/netwerk/protocol/http/src/nsHttpHeaderArray.cpp#252
        //
        case "content-type", "content-length", "user-agent", "referer", "host",
             "authorization", "proxy-authorization", "if-modified-since",
             "if-unmodified-since", "from", "location", "max-forwards",
             "retry-after", "etag", "last-modified", "server", "age", "expires":
            if let _ = caseInsensitiveMap[lowerCaseKey] {
                Log.warning("Duplicate header \(key) discarded")
                break
            }
            fallthrough
            
        // Headers with a simple value that can be merged
        default:
            guard let headerKey = caseInsensitiveMap[lowerCaseKey], let oldValue = headers[headerKey]?.first else {
                set(key, lowerCaseKey: lowerCaseKey, value: value)
                return
            }
            let newValue = oldValue + ", " + value.joined(separator: ", ")
            headers[headerKey]?[0] = newValue
        }
    }
    
    /// Append values to the header
    ///
    /// - Parameter key: the key
    /// - Parameter value: the value
    public func append(_ key: String, value: String) {

        append(key, value: [value])
    }

    /// Gets the header (case insensitive)
    ///
    /// - Parameter key: the key
    ///
    /// - Returns: the value for the key
    private func get(_ key: String) -> [String]? {
        if let headerKey = caseInsensitiveMap[key.lowercased()] {
            return headers[headerKey]
        }
        
        return nil
    }
    
    /// Remove all of the headers
    func removeAll() {
        headers.removeAll(keepingCapacity: true)
        caseInsensitiveMap.removeAll(keepingCapacity: true)
    }
    
    /// Set the header value
    ///
    /// - Parameter key: the key
    /// - Parameter value: the value
    private func set(_ key: String, value: [String]) {
        set(key, lowerCaseKey: key.lowercased(), value: value)
    }
    
    /// Set the header value
    ///
    /// - Parameter key: the key
    /// - Parameter value: the value
    private func set(_ key: String, lowerCaseKey: String, value: [String]) {
        headers[key] = value
        caseInsensitiveMap[key.lowercased()] = key
    }
    
    /// Remove the header by key (case insensitive)
    ///
    /// - Parameter key: the key
    private func remove(_ key: String) {
        
        if let headerKey = caseInsensitiveMap[key.lowercased()] {
            headers[headerKey] = nil
        }
        caseInsensitiveMap[key.lowercased()] = nil
    }
}

/// Variables and methods to implement the Collection protocol
extension HeadersContainer {

    public var startIndex:DictionaryIndex<String, [String]> { return headers.startIndex }

    public var endIndex:DictionaryIndex<String, [String]> { return headers.endIndex }

    public subscript(position: DictionaryIndex<String, [String]>) -> (key: String, value: [String]) {
        get {
            return headers[position]
        }
    }

    public func index(after i: DictionaryIndex<String, [String]>) -> DictionaryIndex<String, [String]> {
        return headers.index(after: i)
    }
}

/// Implement the Sequence protocol
extension HeadersContainer: Sequence {
    public typealias Iterator = DictionaryIterator<String, Array<String>>

    ///
    /// Creates an iterator of the underlying dictionary
    ///
    public func makeIterator() -> HeadersContainer.Iterator {
        return headers.makeIterator()
    }
}
