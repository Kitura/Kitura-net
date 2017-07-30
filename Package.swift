/**
 * Copyright IBM Corporation 2016, 2017
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

import PackageDescription

let package = Package(
    name: "Kitura-net",
    targets: [
        Target(name: "KituraNet", dependencies: ["CHTTPParser"]),
        Target(name: "CHTTPParser", dependencies: [])
    ],
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/LoggerAPI.git", majorVersion: 1, minor: 7),
        .Package(url: "https://github.com/IBM-Swift/BlueSocket.git", majorVersion: 0, minor: 12),
        .Package(url: "https://github.com/adellibovi/CCurl.git", majorVersion: 0, minor: 4),
        .Package(url: "https://github.com/IBM-Swift/BlueSSLService.git", majorVersion: 0, minor: 12)
    ]
)

#if os(Linux)
    package.dependencies.append(
        .Package(url: "https://github.com/IBM-Swift/CEpoll.git", majorVersion: 0, minor: 1))
    package.dependencies.append(
        .Package(url: "https://github.com/IBM-Swift/BlueSignals.git", majorVersion: 0, minor: 9))
#endif
