#include <stdlib.h>
#include <stdio.h>
#include <argp.h>
#include <string.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <arpa/inet.h>

#include "tc_easy.h"
#include "tc_api/tc.h"
#include "tc_api/tc_api.h"

void usage()
{
	printf("Usage: tc-easy [%s | %s] <interface> %s <ip> %s <ip>\n", TC_EASY_ADD_ROUTE_KEYWORD, TC_EASY_REMOVE_ROUTE_KEYWORD, TC_EASY_SRC_ADDR_KEYWORD, TC_EASY_DST_ADDR_KEYWORD);
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
	if (argc <= 2)
	{
		usage();
	}

	char *src_addr_str, *dst_addr_str;
	tc_api_interface interface = {0, 0, 0, 0, 0, 0, 0, ""};

	for (int i = 1; i < argc; i++)
	{
		if (strcmp(argv[i], TC_EASY_ADD_ROUTE_KEYWORD) == 0 ||
			strcmp(argv[i], TC_EASY_REMOVE_ROUTE_KEYWORD) == 0)
		{
			char *name = argv[++i];
			if(assert_interface_name(name) < 0) {
				printf("Interface %s was not found\n", name);
				exit(TC_EASY_INTERFACE_NOT_FOUND);
			}
			strncpy(interface.name, argv[i], 16);
			continue;
		}
		else if (strcmp(argv[i], TC_EASY_SRC_ADDR_KEYWORD) == 0)
		{
			in_addr_t src_addr;
			if(inet_pton(AF_INET, argv[++i], &src_addr) == 0) {
				printf("Source address %s is invalid\n", argv[i]);
				exit(TC_EASY_INVALID_SRC_ADDR);
			}
			interface.src_addr = src_addr;
			src_addr_str = argv[i];
			continue;
		}
		else if (strcmp(argv[i], TC_EASY_DST_ADDR_KEYWORD) == 0)
		{
			in_addr_t dst_addr;
			if(inet_pton(AF_INET, argv[++i], &dst_addr) == 0) {
				printf("Destination address %s is invalid\n", argv[i]);
				exit(TC_EASY_INVALID_DST_ADDR);
			}
			interface.dst_addr = dst_addr;
			dst_addr_str = argv[i];
			continue;
		}
	}

	printf("Adding route on interface %s from %s to %s\n", interface.name, src_addr_str, dst_addr_str);

	exit(TC_EASY_OK);
}