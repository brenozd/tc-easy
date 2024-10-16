#ifndef INCLUDE_SRC_BACKTRACE_H_
#define INCLUDE_SRC_BACKTRACE_H_

#include "common.h"
#include <stdint.h>

void tce_init_backtracer();
int tce_backtrace_callback(void *UNUSED(data), uintptr_t pc, const char *filename, int lineno, const char *function);
void tce_backtrace_error_callback(void *, const char *msg, int errnum);
void tce_backtrace_error_callback_create(void *, const char *msg, int errnum);
void tce_print_backtrace();
void tce_register_signal_handlers();
#endif // INCLUDE_SRC_BACKTRACE_H_
