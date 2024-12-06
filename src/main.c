#include "backtracer.h"
#include "common.h"
#include "tc.h"
#include <limits.h>
#include <stdbool.h>

int main(int UNUSED(argc), char *argv[])
{
#ifndef NDEBUG
  tce_init_backtracer();
  tce_register_signal_handlers();
#endif
  
  return tce_add_netem(argv[1], 50, 98.57f, 10, 0.001f, true);
}
