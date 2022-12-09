#include "tc_api.h"

int tc_api_add_route(tc_api_interface interface) {
    printf("add_tc_route: %s\n", interface.name);
    return TC_API_OK;
}

int tc_api_remove_route(tc_api_interface interface) {
    printf("remove_tc_route: %s\n", interface.name);
    return TC_API_OK;
}