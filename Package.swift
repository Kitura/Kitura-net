// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

/**
 * Copyright IBM Corporation and the Kitura project authors 2016-2020
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
import Foundation

var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/Kitura/LoggerAPI.git", from: "2.0.0"),
    .package(url: "https://github.com/Kitura/BlueSocket.git", from: "2.0.0"),
    .package(url: "https://github.com/Kitura/BlueSSLService.git", from: "2.0.0")
]

var kituraNetDependencies: [Target.Dependency] = [
    .byName(name: "CHTTPParser"),
    .byName(name: "LoggerAPI"),
    .byName(name: "Socket"),
    .byName(name: "SSLService")
]

if ProcessInfo.processInfo.environment["KITURA_IOS"] == nil {
    kituraNetDependencies.append(.target(name: "CCurl"))
}

#if os(Linux)
dependencies.append(contentsOf: [
    .package(url: "https://github.com/Kitura/BlueSignals.git", from: "2.0.0")
    ])

kituraNetDependencies.append(contentsOf: [
    .target(name: "CEpoll"),
    .byName(name: "Signals")
    ])
#endif

var targets: [Target] = [
    .target(
        name: "CHTTPParser"
    ),
    .systemLibrary(
        name: "CCurl"
    ),
    .target(
        name: "KituraNet",
        dependencies: kituraNetDependencies
    ),
    .testTarget(
        name: "KituraNetTests",
        dependencies: ["KituraNet"]
    )
]

#if os(Linux)
targets.append(
    .systemLibrary(name: "CEpoll")
)
#endif

let package = Package(
    name: "Kitura-net",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "KituraNet",
            targets: ["KituraNet"]
        )
    ],
    dependencies: dependencies,
    targets: targets
)
