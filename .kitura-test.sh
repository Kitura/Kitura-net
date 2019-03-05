# Run Kitura-net tests
travis_start "swift_test"
echo ">> Executing Kitura-net tests"
swift test
SWIFT_TEST_STATUS=$?
travis_end
if [ $SWIFT_TEST_STATUS -ne 0 ]; then
  echo ">> swift test command exited with $SWIFT_TEST_STATUS"
  # Return a non-zero status so that Package-Builder will generate a backtrace
  return $SWIFT_TEST_STATUS
fi

# Clone Kitura
set -e
echo ">> Building Kitura"
travis_start "swift_build_kitura"
cd .. && git clone https://github.com/IBM-Swift/Kitura && cd Kitura

# Build once
swift build

# Edit package Kitura-net to point to the current branch
echo ">> Editing Kitura package to use latest Kitura-net"
swift package edit Kitura-net --path ../Kitura-net
travis_end
set +e

# Run Kitura tests
travis_start "swift_test_kitura"
echo ">> Executing Kitura tests"
swift test
SWIFT_TEST_STATUS=$?
travis_end
if [ $SWIFT_TEST_STATUS -ne 0 ]; then
  echo ">> swift test command exited with $SWIFT_TEST_STATUS"
  # Return a non-zero status so that Package-Builder will generate a backtrace
  return $SWIFT_TEST_STATUS
fi

# Move back to the original build directory. This is needed on macOS builds for the subsequent swiftlint step.
cd ../Kitura-net
