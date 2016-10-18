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

import Socket

public protocol Server {

    weak var delegate: ServerDelegate? { get set }

    weak var lifecycleDelegate: ServerLifecycleDelegate? { get set }

    var port: Int? { get }

    func listen(port: Int, errorHandler: ((Swift.Error) -> Void)?)

    static func listen(port: Int, delegate: ServerDelegate, lifecycleDelegate: ServerLifecycleDelegate?, errorHandler: ((Swift.Error) -> Void)?) -> Server

    func stop()
}
