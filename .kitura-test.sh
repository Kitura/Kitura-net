set -ex

# Run Kitura-net tests
swift test

# Clone Kitura
cd .. && git clone https://github.com/IBM-Swift/Kitura && cd Kitura

# Build once
swift build

# Edit package Kitura-net to point to the current branch
swift package edit Kitura-net --path ../Kitura-net

# Run Kitura tests
swift test

# Move back to the original build directory. This is needed on macOS builds for the subsequent swiftlint step.
cd ../Kitura-net
