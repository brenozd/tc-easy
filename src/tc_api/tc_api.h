#ifndef _TC_API_H_
#define _TC_API_H_

#include <stdio.h>
#include <netinet/in.h>

#include "include/utils.h"
#include "tc/tc_util.h"
#include "tc/tc_common.h"

#define TC_API_OK 0
#define TC_API_ERROR 1

#define TC_API_ADD_REQUEST_TYPE 1
#define TC_API_REMOVE_REQUEST_TYPE 2
#define TC_API_LIST_REQUEST_TYPE 3

#define TC_API_ROUTE_INIT {0, 0, 0, 0, 0, 0, 0, ""}

typedef struct route_t
{
	uint latency, jitter, packet_loss,
		bw_download, bw_upload;
	in_addr_t src_addr, dst_addr;
	char interface_name[16];
} tc_api_route;

typedef struct tc_api_request_t {
    uint type;
    tc_api_route route;
} tc_api_request;

int tc_api_add_route(tc_api_route route);
int tc_api_remove_route(tc_api_route route);
int tc_api_list_routes(tc_api_route route);

#endif