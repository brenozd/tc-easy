#ifndef INCLUDE_SRC_COMMON_H_
#define INCLUDE_SRC_COMMON_H_

#include "errno.h"
#include "string.h"

#ifdef __GNUC__
#define UNUSED(x) UNUSED_##x __attribute__((__unused__))
#else
#define UNUSED(x) UNUSED_##x
#endif

#ifdef __GNUC__
#define UNUSED_FUNCTION(x) __attribute__((__unused__)) UNUSED_##x
#else
#define UNUSED_FUNCTION(x) UNUSED_##x
#endif

#define HANDLE_ERRNO()                                                                                                         \
  do {                                                                                                                         \
    int errno_tmp_ = errno;                                                                                                    \
    const char *func_name = __func__;                                                                                          \
    fprintf(stderr, "Caught errno: [%d - %s] in function '%s'\n", errno_tmp_, strerror(errno_tmp_), func_name);                  \
  } while (0)

#endif // INCLUDE_SRC_COMMON_H_
