#include "backtracer.h"
#include "common.h"
#include "tc.h"

int main(int UNUSED(argc), char *argv[])
{
  tce_init_backtracer();
  tce_register_signal_handlers();

  return tce_add_tbf(argv[1]);
}
