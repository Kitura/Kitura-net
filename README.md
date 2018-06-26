<p align="center">
<a href="http://kitura.io/">
<img src="https://raw.githubusercontent.com/IBM-Swift/Kitura/master/Sources/Kitura/resources/kitura-bird.svg?sanitize=true" height="100" alt="Kitura">
</a>
</p>

<p align="center">
    <a href="https://ibm-swift.github.io/Kitura-net/index.html">
    <img src="https://img.shields.io/badge/apidoc-KituraNet-1FBCE4.svg?style=flat" alt="APIDoc">
    </a>
    <a href="https://travis-ci.org/IBM-Swift/Kitura-net">
    <img src="https://travis-ci.org/IBM-Swift/Kitura-net.svg?branch=master" alt="Build Status - Master">
    </a>
    <img src="https://img.shields.io/badge/os-macOS-green.svg?style=flat" alt="macOS">
    <img src="https://img.shields.io/badge/os-linux-green.svg?style=flat" alt="Linux">
    <img src="https://img.shields.io/badge/license-Apache2-blue.svg?style=flat" alt="Apache 2">
    <a href="http://swift-at-ibm-slack.mybluemix.net/">
    <img src="http://swift-at-ibm-slack.mybluemix.net/badge.svg" alt="Slack Status">
    </a>
</p>

# Kitura-Net

The Kitura-net module contains logic for sending and receiving HTTP requests. It also contains the structure for listening on a port and sending requests to a delegate for processing. It can be used to create HTTP/CGI servers on specific ports, and provides HTTP functionality.

We expect most of our users to require higher level concepts such as routing, templates and middleware, these are not provided in Kitura-net, if you want to use those facilities you should be coding at the Kitura level, for this please see the [Kitura](https://github.com/IBM-Swift/Kitura) project. Kitura-net underpins Kitura which offers a higher abstraction level to users.

Kitura-net utilises the [BlueSocket](https://github.com/IBM-Swift/BlueSocket) framework, the [BlueSSLService](https://github.com/IBM-Swift/BlueSSLService.git) framework and [CCurl](https://github.com/IBM-Swift/CCurl.git).

## Features

- Port Listening
- FastCGI Server support
- HTTP Server support (request and response)

## Usage

#### Add dependencies

Add the `Kitura-net` package to the dependencies within your application’s `Package.swift` file. Substitute `"x.x.x"` with the latest `Kitura-net` [release](https://github.com/IBM-Swift/Kitura-net/releases).

```swift
.package(url: "https://github.com/IBM-Swift/Kitura-net.git", from: "x.x.x")
```

Add `KituraNet` to your target's dependencies:

```swift
.target(name: "example", dependencies: ["KituraNet"]),
```

#### Import package

  ```swift
  import KituraNet
  ```

## Contributing to Kitura-net

All improvements to Kitura-net are very welcome! Here's how to get started with developing Kitura-net itself.

1. Clone this repository.

`$ git clone https://github.com/IBM-Swift/Kitura-net && cd Kitura-net`

2. Build and run tests.

`$ swift test`

You can find more info on contributing to Kitura in our [contributing guidelines](https://github.com/IBM-Swift/Kitura/blob/master/.github/CONTRIBUTING.md).

## API Documentation
For more information visit our [API reference](https://ibm-swift.github.io/Kitura-net/index.html).

## Community

We love to talk server-side Swift, and Kitura. Join our [Slack](http://swift-at-ibm-slack.mybluemix.net/) to meet the team!

## License
This library is licensed under Apache 2.0. Full license text is available in [LICENSE](https://github.com/IBM-Swift/Kitura-net/blob/master/LICENSE.txt).
