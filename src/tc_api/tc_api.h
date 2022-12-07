#ifndef _TC_API_H_
#define _TC_API_H_

#include <netinet/in.h>

#define TC_API_OK 0
#define TC_API_ERROR 1

int tc_add_route(/*in_addr_t src_ip, in_addr_t dest_ip, uint latency, uint jitter, uint packet_loss, uint upload_bandwidth, uint download_bandwidth*/);
int tc_remove_route(in_addr_t src_ip, in_addr_t dest_ip);

#endif