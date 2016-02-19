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

#ifndef CurlHelpers_h
#define CurlHelpers_h

#import <curl/curl.h>

#define CURL_TRUE  1
#define CURL_FALSE 0

CURLcode curlHelperSetOptBool(CURL *curl, CURLoption option, int yesNo);
CURLcode curlHelperSetOptHeaders(CURL *curl, struct curl_slist *headers);
CURLcode curlHelperSetOptInt(CURL *curl, CURLoption option, long data);
CURLcode curlHelperSetOptString(CURL *curl, CURLoption option, char *data);
CURLcode curlHelperSetOptReadFunc(CURL *curl, void *userData, size_t (*read_cb) (char *buffer, size_t size, size_t nitems, void *userdata));
CURLcode curlHelperSetOptWriteFunc(CURL *curl, void *userData, size_t (*write_cb) (char *ptr, size_t size, size_t nmemb, void *userdata));


CURLcode curlHelperGetInfoCString(CURL *curl, CURLINFO info, char **data);
CURLcode curlHelperGetInfoLong(CURL *curl, CURLINFO info, long *data);


#endif /* CurlHelpers_h */
