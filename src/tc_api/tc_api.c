#include "tc_api.h"

#include <stdio.h>
int tc_add_route(/*in_addr_t src_ip, in_addr_t dest_ip, uint latency, uint jitter, uint packet_loss, uint upload_bandwidth, uint download_bandwidth*/) {
    printf("add_tc_route\n");
    return TC_API_OK;
}

int tc_remove_route(in_addr_t src_ip, in_addr_t dest_ip) {
    printf("remove_tc_route\n");
    return TC_API_ERROR;
}