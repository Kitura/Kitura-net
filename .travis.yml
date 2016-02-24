# .travis.yml for Kitura Swift Packages

sudo: true

# whitelist
branches:
  only:
    - master
    - develop

before_install:
  - git clone https://github.com/IBM-Swift/Kitura-CI.git

script:
  - echo "About to trigger build for the Kitura repository..."
  - cd Kitura-CI && ./kitura-build-trigger.sh $TRAVIS_BRANCH $TRAVIS_TOKEN
  - echo "Request to build Kitura sent!"
