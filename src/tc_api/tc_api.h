#ifndef _TC_API_H_
#define _TC_API_H_

#include <stdio.h>
#include <netinet/in.h>
#include "tc.h"

#define TC_API_OK 0
#define TC_API_ERROR 1

int tc_api_add_route(tc_api_interface interface);
int tc_api_remove_route(tc_api_interface interface);

#endif