#include "backtracer.h"
#include "common.h"
#include "tc.h"

int main(int UNUSED(argc), char *UNUSED(argv[]))
{
  tce_init_backtracer();
  tce_register_signal_handlers();

  return tce_add_tbf("enp45s0");
}
