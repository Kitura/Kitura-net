//
//  CurlHelpers.c
//  net
//
//  Created by Samuel Kallner on 11/19/15.
//  Copyright © 2015 IBM. All rights reserved.
//

#include <stdio.h>

#include "CurlHelpers.h"



CURLcode curlHelperSetOptBool(CURL *curl, CURLoption option, int yesNo) {
    return curl_easy_setopt(curl, option, yesNo == CURL_TRUE ? 1L : 0L);
}

CURLcode curlHelperSetOptHeaders(CURL *curl, struct curl_slist *headers) {
    return curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
}

CURLcode curlHelperSetOptInt(CURL *curl, CURLoption option, long data) {
    return curl_easy_setopt(curl, option, data);
}

CURLcode curlHelperSetOptString(CURL *curl, CURLoption option, char *data) {
    return curl_easy_setopt(curl, option, data);
}

CURLcode curlHelperSetOptReadFunc(CURL *curl, void *userData, size_t (*read_cb) (char *buffer, size_t size, size_t nitems, void *userdata)) {
    CURLcode rc = curl_easy_setopt(curl, CURLOPT_READDATA, userData);
    if  (rc == CURLE_OK) {
        rc = curl_easy_setopt(curl, CURLOPT_READFUNCTION, read_cb);
    }
    return rc;
}

CURLcode curlHelperSetOptWriteFunc(CURL *curl, void *userData, size_t (*write_cb) (char *ptr, size_t size, size_t nmemb, void *userdata)) {
    CURLcode rc = curl_easy_setopt(curl, CURLOPT_HEADER, 1);
    if  (rc == CURLE_OK)  {
        rc = curl_easy_setopt(curl, CURLOPT_WRITEDATA, userData);
        if  (rc == CURLE_OK) {
            rc = curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
        }
    }
    return rc;
}


CURLcode curlHelperGetInfoCString(CURL *curl, CURLINFO info, char **data) {
    return curl_easy_getinfo(curl, info, data);
}

CURLcode curlHelperGetInfoLong(CURL *curl, CURLINFO info, long *data) {
    return curl_easy_getinfo(curl, info, data);
}