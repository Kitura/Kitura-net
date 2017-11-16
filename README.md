[![Kitura](https://raw.githubusercontent.com/IBM-Swift/Kitura-net/doc_overhaul/Documentation/KituraLogo.png)](http://kitura.io)

# Kitura-net

[![Build Status - Master](https://travis-ci.org/IBM-Swift/Kitura-net.svg?branch=master)](https://travis-ci.org/IBM-Swift/Kitura-net)
[![codecov](https://codecov.io/gh/IBM-Swift/Kitura-net/branch/master/graph/badge.svg)](https://codecov.io/gh/IBM-Swift/Kitura-net)
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)
![Apache 2](https://img.shields.io/badge/license-Apache2-blue.svg?style=flat)


## Summary

The Kitura-net module contains logic for sending and receiving HTTP requests. It also contains the structure for listening on a port and sending requests to a delegate for processing. It can be used to create HTTP/CGI Servers on specific ports, and provides HTTP functionality.

If you require Routing, Templates or Middleware functionality, please see the [Kitura](https://github.com/IBM-Swift/Kitura) project.

Kitura-net utilises the [BlueSocket](https://github.com/IBM-Swift/BlueSocket) framework, the [BlueSSLService](https://github.com/IBM-Swift/BlueSSLService.git) framework and [CCurl](https://github.com/IBM-Swift/CCurl.git).

## Features

- Port Listening
- FastCGI Server support
- HTTP Server support (request and response)

## Getting Started

Visit [www.kitura.io](http://www.kitura.io/) for reference documentation.

## Contributing to Kitura-net

All improvements to Kitura-net are very welcome! Here's how to get started with developing Kitura-net itself.

1. Clone this repository.

`$ git clone https://github.com/IBM-Swift/Kitura-net`

2. Build and run tests.

`$ swift test`

You can find more info on contributing to Kitura in our [contributing guidelines](https://github.com/IBM-Swift/Kitura/blob/master/.github/CONTRIBUTING.md).
