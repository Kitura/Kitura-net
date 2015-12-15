//
//  utils.m
//  EnterpriseSwift
//
//  Created by Ira Rosen on 7/10/15.
//  Copyright © 2015 IBM. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <http_parser.h>

#include "utils.h"

unsigned int get_upgrade_value(http_parser* parser) {
    return parser->upgrade;
}

unsigned int get_status_code(http_parser* parser) {
    return parser->status_code;
}

const char* get_method(http_parser* parser) {
    return http_method_str(parser->method);
}

int http_parser_parse_url_url (const char *buf, size_t buflen,
                               int is_connect,
                               struct http_parser_url_url *u) {
    struct http_parser_url url;
    int res = http_parser_parse_url (buf, buflen,
                                         is_connect, &url);
    u->field_set = url.field_set;
    u->port = url.port;
    memcpy(u->field_data, url.field_data, sizeof(url.field_data));
    
    return res;
}
