#ifndef __TC_H__
#define __TC_H__

#include <netinet/in.h>

typedef struct interface_t
{
	uint latency, jitter, packet_loss,
		bw_download, bw_upload;
	in_addr_t src_addr, dst_addr;
	char name[16];
} tc_api_interface;

#endif