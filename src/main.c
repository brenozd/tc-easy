#include <stdlib.h>
#include <stdio.h>
#include <argp.h>
#include <string.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <arpa/inet.h>

#include "tc_easy.h"
#include "tc_api/tc_api.h"

void usage(uint subcommand)
{
	switch(subcommand) {
		case TC_API_ADD_REQUEST_TYPE: //ADD
			printf("Usage: tc-easy %s <interface> %s <ip> %s <ip>\n", TC_EASY_ADD_ROUTE_KEYWORD, TC_EASY_SRC_ADDR_KEYWORD, TC_EASY_DST_ADDR_KEYWORD);
			break;
		case TC_API_REMOVE_REQUEST_TYPE: // REMOVE
			printf("Usage: tc-easy %s <interface> %s <ip> %s <ip>\n", TC_EASY_REMOVE_ROUTE_KEYWORD, TC_EASY_SRC_ADDR_KEYWORD, TC_EASY_DST_ADDR_KEYWORD);
			break; //LIST
		case TC_API_LIST_REQUEST_TYPE:
			printf("Usage: tc-easy %s <interface>\n", TC_EASY_LIST_ROUTES_KEYWORD);
			break;
		default:
			printf("Usage: tc-easy [%s | %s | %s]\n", TC_EASY_ADD_ROUTE_KEYWORD, TC_EASY_REMOVE_ROUTE_KEYWORD, TC_EASY_LIST_ROUTES_KEYWORD);
			break;
	}
	exit(TC_EASY_ERROR);
}

// TODO: This should allow only 16 bytes according to ifr_ifname
int assert_interface_name(char *interface_name)
{
	struct ifreq interface;
	int sock = -1;
	if ((sock = socket(AF_INET, SOCK_STREAM, 0)) == -1)
	{
		perror("assert_interface_name socket:");
		return -1;
	}

	memset(&interface, 0, sizeof(interface));
	strcpy(interface.ifr_ifrn.ifrn_name, interface_name);
	if (ioctl(sock, SIOCGIFINDEX, &interface) < 0)
	{
		// perror("assert_interface_name ioctl:");
		return -1;
	}
	return interface.ifr_ifindex;
}

int main(int argc, char *argv[])
{
	if (argc <= 1)
	{
		usage(0);
	}

	char *src_addr_str, *dst_addr_str;
	tc_api_request request;
	request.type = 0;

	for (int i = 1; i < argc; i++)
	{
		if (strcmp(argv[i], TC_EASY_ADD_ROUTE_KEYWORD) == 0)
		{
			if(request.type != 0) {
				printf("Invalid command construction: another subcommand was already provided\n");
				usage(TC_API_ADD_REQUEST_TYPE);
				return TC_EASY_INVALID_CMD;
			}
			if(i+1 >= argc) {
				printf("Required value for argument %s was not provided\n", argv[i]);
				return TC_EASY_REQUIRED_VALUE;
			}
			char *name = argv[++i];
			if(assert_interface_name(name) < 0) {
				printf("Interface %s was not found\n", name);
				return TC_EASY_INTERFACE_NOT_FOUND;
			}
			request.type = TC_API_ADD_REQUEST_TYPE;
			strncpy(request.route.interface_name, argv[i], 16);
			continue;
		}
		else if (strcmp(argv[i], TC_EASY_REMOVE_ROUTE_KEYWORD) == 0)
		{
			if(request.type != 0) {
				printf("Invalid command construction: another subcommand was already provided\n");
				usage(TC_API_REMOVE_REQUEST_TYPE);
				return TC_EASY_INVALID_CMD;
			}
			if(i+1 >= argc) {
				printf("Required value for argument %s was not provided\n", argv[i]);
				return TC_EASY_REQUIRED_VALUE;
			}
			char *name = argv[++i];
			if(assert_interface_name(name) < 0) {
				printf("Interface %s was not found\n", name);
				return TC_EASY_INTERFACE_NOT_FOUND;
			}
			request.type = TC_API_REMOVE_REQUEST_TYPE;
			strncpy(request.route.interface_name, argv[i], 16);
			continue;
		}
		else if (strcmp(argv[i], TC_EASY_LIST_ROUTES_KEYWORD) == 0)
		{
			if(request.type != 0) {
				printf("Invalid command construction: another subcommand was already provided\n");
				usage(TC_API_LIST_REQUEST_TYPE);
				return TC_EASY_INVALID_CMD;
			}
			if(i+1 >= argc) {
				printf("Required value for argument %s was not provided\n", argv[i]);
				return TC_EASY_REQUIRED_VALUE;
			}
			char *name = argv[++i];
			if(assert_interface_name(name) < 0) {
				printf("Interface %s was not found\n", name);
				return TC_EASY_INTERFACE_NOT_FOUND;
			}
			if(argc > 2) {
				if(assert_interface_name(name) < 0) {
					printf("Interface %s was not found\n", name);
					return TC_EASY_INTERFACE_NOT_FOUND;
				}
				strncpy(request.route.interface_name, argv[i], 16);
			}
			request.type = TC_API_LIST_REQUEST_TYPE;
			tc_api_list_routes(request.route);
			return TC_EASY_OK;
		}
		else if (strcmp(argv[i], TC_EASY_SRC_ADDR_KEYWORD) == 0)
		{
			in_addr_t src_addr;
			if(request.route.src_addr != 0) {
				printf("Invalid command contruction: another source IP address already set to %s\n", src_addr_str);
				usage(request.type);
				return TC_EASY_INVALID_CMD;
			}
			if(i+1 >= argc) {
				printf("Required value for argument %s was not provided\n", argv[i]);
				return TC_EASY_REQUIRED_VALUE;
			}
			if(inet_pton(AF_INET, argv[++i], &src_addr) == 0) {
				printf("Source address %s is invalid\n", argv[i]);
				return TC_EASY_INVALID_SRC_ADDR;
			}
			request.route.src_addr = src_addr;
			src_addr_str = argv[i];
			continue;
		}
		else if (strcmp(argv[i], TC_EASY_DST_ADDR_KEYWORD) == 0)
		{
			in_addr_t dst_addr;
			if(request.route.dst_addr != 0) {
				printf("Invalid command contruction: another destination IP address already set to %s\n", dst_addr_str);
				usage(request.type);
				return TC_EASY_INVALID_CMD;
			}
			if(i+1 >= argc) {
				printf("Required value for argument %s was not provided\n", argv[i]);
				return TC_EASY_REQUIRED_VALUE;
			}
			if(inet_pton(AF_INET, argv[++i], &dst_addr) == 0) {
				printf("Destination address %s is invalid\n", argv[i]);
				return TC_EASY_INVALID_DST_ADDR;
			}
			request.route.dst_addr = dst_addr;
			dst_addr_str = argv[i];
			continue;
		}
	}

	if(request.type == 0) {
		usage(request.type);
		return TC_EASY_ERROR;
	}
	printf("Adding route on interface %s from %s to %s\n", request.route.interface_name, src_addr_str, dst_addr_str);

	return TC_EASY_OK;
}