//
//  CurlHelpers.h
//  net
//
//  Created by Samuel Kallner on 11/19/15.
//  Copyright © 2015 IBM. All rights reserved.
//

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
