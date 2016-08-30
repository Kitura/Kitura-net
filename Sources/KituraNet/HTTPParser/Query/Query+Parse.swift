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

import Foundation

extension String {

    fileprivate var parameter: String? {
        let urlCharacterSet = CharacterSet(charactersIn: " \"\n")
        return self.removingPercentEncoding?.trimmingCharacters(in: urlCharacterSet)
    }
}

//MARK: query parsing
extension Query {

    public init(fromText query: String?) {
        self.init([:])

        guard let query = query else {
            return
        }
        Query.parse(fromText: query, into: &self)
    }

    static private func parse(fromText query: String, into root: inout Query) {
        let pairs = query.components(separatedBy: "&")

        for pair in pairs {
            let pairArray = pair.components(separatedBy: "=")

            guard pairArray.count == 2,
                let valueString = pairArray[1].parameter,
                !valueString.isEmpty,
                let key = pairArray[0].parameter,
                !key.isEmpty else {
                    continue
            }

            let value = Query(valueString)
            if case .null = value.type { continue }
            Query.parse(root: &root, key: key, value: value)
        }
    }

    static private func parse(root: inout Query, key: String?, value: Query) {
        if let key = key,
            let regex = Query.indexedParameterRegex,
            let match = regex.firstMatch(in: key, options: [], range: NSMakeRange(0, key.characters.count)) {
                let nsKey = NSString(string: key)

            #if os(Linux)
                let matchRange = match.range(at: 0)
                let parameterRange = match.range(at: 1)
                let indexRange = match.range(at: 2)
            #else
                let matchRange = match.rangeAt(0)
                let parameterRange = match.rangeAt(1)
                let indexRange = match.rangeAt(2)
            #endif

                guard let parameterKey = nsKey.substring(with: parameterRange).parameter,
                    let indexKey = nsKey.substring(with: indexRange).parameter else {
                        return
                }

                let nextKey = nsKey.replacingCharacters(in: matchRange, with: indexKey)

                if !indexKey.isEmpty {
                    Query.parse(root: &root,
                        key: nextKey,
                        parameterKey: parameterKey,
                        defaultRaw: [:],
                        value: value) { $0.dictionary }
                } else {
                    Query.parse(root: &root,
                        key: nextKey,
                        parameterKey: parameterKey,
                        defaultRaw: [],
                        value: value) { $0.array }
                }
        } else if let key = key,
            !key.isEmpty {
                root[key] = value
        } else if case .array(var existingArray) = root.type {
            existingArray.append(value.object)
            root = Query(existingArray)
        } else {
            root = value
        }
    }

    static private func parse(root: inout Query,
        key: String,
        parameterKey: String,
        defaultRaw: Any,
        value: Query,
        raw rawClosure: (Query) -> Any?) {
            var newParameter: Query

            if !parameterKey.isEmpty,
                let raw = rawClosure(root[parameterKey]) {
                    newParameter = Query(raw)
            } else if parameterKey.isEmpty,
                let raw = root.array?.first {
                    newParameter = Query(raw)
            } else {
                newParameter = Query(defaultRaw)
            }

            Query.parse(root: &newParameter, key: key, value: value)

            if !parameterKey.isEmpty {
                root[parameterKey] = newParameter
            } else if case .array(var array) = root.type {
                if array.count > 0 {
                    array[0] = newParameter.object
                } else {
                    array.append(newParameter.object)
                }

                root = Query(array)
            }
    }
}
