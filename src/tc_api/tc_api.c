#include "tc_api.h"

int tc_api_add_route(tc_api_route route) {
    printf("add_tc_route: %s\n", route.interface_name);
    return TC_API_OK;
}

int tc_api_remove_route(tc_api_route route) {
    printf("remove_tc_route: %s\n", route.interface_name);
    return TC_API_OK;
}

int tc_api_list_routes(tc_api_route route) {
    printf("list_route: %s\n", route.interface_name);
    return TC_API_OK;
}