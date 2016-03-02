# Copyright IBM Corporation 2016
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Makefile
# This Makefile is used to build the necessary shims or helpers around C libraries before Swift Package Manager is called.

ROOT_DIR=.
BUILD_DIR=${ROOT_DIR}/.build/debug

HTTP_PARSER_MODULE=$(wildcard ${ROOT_DIR}/Packages/Kitura-HttpParserHelper-*)
CURL_MODULE=$(wildcard ${ROOT_DIR}/Packages/Kitura-CurlHelpers-*)

# Include where users install header files (i.e. this is where dispatch/dispatch.h and pcre2 should be located).
INCLUDE_DIR=/usr/local/include
#detect OS
UNAME := $(shell uname)

ifeq ($(UNAME),Darwin)
CLANG_EXTRA=-mmacosx-version-min=10.10
EXTRA_LINK=-Xlinker -L/usr/local/lib
else
CLANG_EXTRA=
EXTRA_LINK=-Xlinker -ldispatch
endif

all: setup kitura

setup:
	mkdir -p ${BUILD_DIR}

kitura: $(BUILD_DIR)/libcurlHelpers.a $(BUILD_DIR)/libhttpParserHelper.a 
# Runs the swift build for the right system 
	swift build -Xcc -fblocks -Xlinker -L${BUILD_DIR} ${EXTRA_LINK}

$(BUILD_DIR)/libcurlHelpers.a:
	clang -c -fPIC ${CLANG_EXTRA} ${CURL_MODULE}/CurlHelpers.c -o ${BUILD_DIR}/CurlHelpers.o
	ar rcs ${BUILD_DIR}/libcurlHelpers.a ${BUILD_DIR}/CurlHelpers.o
ifeq ($(UNAME),Darwin)
	g++ -dynamiclib -undefined suppress -flat_namespace ${BUILD_DIR}/CurlHelpers.o -o ${BUILD_DIR}/libcurlHelpers.dylib
endif

$(BUILD_DIR)/libhttpParserHelper.a: 
	clang -c -fPIC ${CLANG_EXTRA} -I${INCLUDE_DIR} ${HTTP_PARSER_MODULE}/utils.c -o ${BUILD_DIR}/httpParserHelper.o
	ar rcs ${BUILD_DIR}/libhttpParserHelper.a ${BUILD_DIR}/httpParserHelper.o
ifeq ($(UNAME),Darwin)
	g++ -dynamiclib -undefined suppress -flat_namespace ${BUILD_DIR}/httpParserHelper.o -o ${BUILD_DIR}/libhttpParserHelper.dylib
endif

clean:
	rm -rf ${BUILD_DIR}
	mkdir ${BUILD_DIR}

.PHONY: clean


