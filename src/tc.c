#include "tc.h"
#include <limits.h>
#include <stdbool.h>
#include "netlink/route/link.h"
#include "netlink/route/qdisc.h"
#include "netlink/route/qdisc/tbf.h"
#include "netlink/route/qdisc/netem.h"
#include <linux/netlink.h>
#include <netlink/socket.h>

static struct nl_sock* _tce_nl_socket = NULL;
static struct nl_cache* _tce_nl_link_cache = NULL;

bool _tce_init_nl_socket() {
  if(_tce_nl_socket != NULL)
    return true;

  _tce_nl_socket = nl_socket_alloc();
  if(_tce_nl_socket == NULL) {
    fprintf(stderr, "Failed to allocate netlink socket\n");
    return false;
  }

  int socket_connected = nl_connect(_tce_nl_socket, NETLINK_ROUTE);
  if(socket_connected < 0) {
    fprintf(stderr, "Failed to connect to netlink socket: %s\n", nl_geterror(socket_connected));
    nl_socket_free(_tce_nl_socket);
    _tce_nl_socket = NULL;
    return false;
  }

  return true;
}

bool _tce_init_link_cache() {
  if(!_tce_init_nl_socket())
    return false;

  int rc = rtnl_link_alloc_cache(_tce_nl_socket, AF_UNSPEC, &_tce_nl_link_cache);
  if(rc < 0) {
    fprintf(stderr, "Failed to allocate netlink link cache\n");
    return false;
  }
  return true;
}

/*
* TODO: Allow to set distribution for delay
* TODO: Calculate and set limit for netem based on interface throughput and maximum delay
*/
bool tce_add_netem(char dev[], float delay_ms, float delay_correlation_pct, float jitter_ms, float loss_pct, bool replace) {
  if(!_tce_init_link_cache())
    return false;

  struct rtnl_link* device;
  device = rtnl_link_get_by_name(_tce_nl_link_cache, dev);
  if(device == NULL) {
    fprintf(stderr, "Failed to get network device with name %s\n", dev);
    return false;
  }

  struct rtnl_qdisc* qdisc;
  qdisc = rtnl_qdisc_alloc();
  if(qdisc == NULL) {
    fprintf(stderr, "Failed to allocate queueing discipline\n");
    rtnl_link_put(device);
    return false;
  }

  uint32_t parent_handle = 0;
  int rc = rtnl_tc_str2handle("root", &parent_handle);
  if(rc < 0) {
    fprintf(stderr, "Failed to get root handle for network device %s: %s\n", dev, nl_geterror(rc));
    rtnl_qdisc_put(qdisc);
    rtnl_link_put(device);
    return false;
  }

  struct rtnl_tc* tc = TC_CAST(qdisc);
  rtnl_tc_set_link(tc, device);
  rtnl_tc_set_parent(tc, parent_handle);
  
  rc = rtnl_tc_set_kind(tc, "netem");
  if(rc < 0) {
    fprintf(stderr, "Failed to set qdisc kind to \"netem\" on network device %s: %s\n", dev, nl_geterror(rc));
    return false;
  }

  if(delay_ms > 0)
    rtnl_netem_set_delay(qdisc, (int)(delay_ms*1000));

  if(jitter_ms > 0) 
    rtnl_netem_set_jitter(qdisc, (int)(jitter_ms*1000));

  /*
   * For percentages, libnetlink works mapping UINT_MAX as 100%, so we do the math to make the function call more readable
  */
  if(delay_correlation_pct > 0) {
    if(delay_correlation_pct > 100) {
      fprintf(stderr, "Delay correlation, represented as percentage, must be a integer between 0 and 100");
      return false;
    }

    float correlation_factor = delay_correlation_pct / 100.0f;
    uint real_correlation = (uint)(correlation_factor * UINT_MAX);
    rtnl_netem_set_delay_correlation(qdisc, (int)real_correlation);
  }

  if(loss_pct > 0) {
    if(loss_pct > 100) {
      fprintf(stderr, "Packet Loss, represented as percentage, must be a integer between 0 and 100");
      return false;
    }

    float correlation_factor = loss_pct / 100.0f;
    uint real_loss = (uint)(correlation_factor * UINT_MAX);
    rtnl_netem_set_loss(qdisc, (int)real_loss);
  }

  int flags = NLM_F_CREATE;
  if(replace)
    flags |= NLM_F_REPLACE;
  else
    flags |= NLM_F_EXCL;

  rc = rtnl_qdisc_add(_tce_nl_socket, qdisc, flags);
  if (rc < 0) {
    fprintf(stderr, "Failed to add netem qdisc to device %s: %s\n", dev, nl_geterror(rc));
    rtnl_qdisc_put(qdisc);
    rtnl_link_put(device);
    return false;
  }

  rtnl_qdisc_put(qdisc);
  rtnl_link_put(device);

  return true;
}

bool tce_add_tbf(char dev[]) {
  if(!_tce_init_link_cache())
    return false;

  struct rtnl_link* device;
  device = rtnl_link_get_by_name(_tce_nl_link_cache, dev);
  if(device == NULL) {
    fprintf(stderr, "Failed to get network device with name %s\n", dev);
    return false;
  }

  struct rtnl_qdisc* qdisc;
  qdisc = rtnl_qdisc_alloc();
  if(qdisc == NULL) {
    fprintf(stderr, "Failed to allocate queueing discipline\n");
    rtnl_link_put(device);
    return false;
  }

  uint32_t parent_handle = 0;
  int rc = rtnl_tc_str2handle("root", &parent_handle);
  if(rc < 0) {
    fprintf(stderr, "Failed to get root handle for network device %s: %s\n", dev, nl_geterror(rc));
    rtnl_qdisc_put(qdisc);
    rtnl_link_put(device);
    return false;
  }

  struct rtnl_tc* tc = TC_CAST(qdisc);
  rtnl_tc_set_link(tc, device);
  rtnl_tc_set_parent(tc, parent_handle);

  
  rc = rtnl_tc_set_kind(tc, "tbf");
  if(rc < 0) {
    fprintf(stderr, "Failed to set qdisc kind to \"tbf\" on network device %s: %s\n", dev, nl_geterror(rc));
    return false;
  }

  int rate = 1 * 1024 * 1024;       // 1 MB/s
  int burst = 2 * 1024 * 1024;     // 2 MB
  int limit = 2 * 1024 * 1024;     // Limite igual ao tamanho do bucket
  rtnl_qdisc_tbf_set_rate(qdisc, rate, burst, 0);
  rtnl_qdisc_tbf_set_limit(qdisc, limit);

  rc = rtnl_qdisc_add(_tce_nl_socket, qdisc, NLM_F_CREATE | NLM_F_EXCL);
  if (rc < 0) {
    fprintf(stderr, "Failed to add TBF qdisc to device %s: %s\n", dev, nl_geterror(rc));
    rtnl_qdisc_put(qdisc);
    rtnl_link_put(device);
    return false;
  }

  rtnl_qdisc_put(qdisc);
  rtnl_link_put(device);
  return true;
}

