#include "backtracer.h"
#include <stdio.h>
#include <stdlib.h>

void f3() { abort(); }
void f2() { f3(); }
void f1() { f2(); }

int main(int argc, char *argv[]) {
  tce_register_signal_handlers();
  tce_init_backtracer();
  printf("Hello\n");
  f1();
}
