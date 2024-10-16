#include "backtracer.h"
#include "backtrace.h"
#include "common.h"
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void *__tce_backtrace_state = NULL;

void tce_init_backtracer() {
  __tce_backtrace_state = backtrace_create_state(NULL, 0, tce_backtrace_error_callback_create, NULL);
  if (!__tce_backtrace_state) {
    fprintf(stderr, "Failed to initialize backtrace engine\n");
    abort();
  }
}

int tce_backtrace_callback(void *UNUSED(data), uintptr_t pc, const char *filename, int lineno, const char *function) {
  if (!function || !filename)
    return 0;

  printf("#%p - %s() at %s (line %d)\n", (void *)pc, function, filename, lineno);
  return 0;
}

void tce_backtrace_error_callback(void *UNUSED(data), const char *msg, int errnum) {
  printf("Error %d occurred when getting the stacktrace: %s", errnum, msg);
}

void tce_backtrace_error_callback_create(void *UNUSED(data), const char *msg, int errnum) {
  printf("Error %d occurred when initializing the stacktrace: %s", errnum, msg);
}

void tce_print_backtrace() {
  if (!__tce_backtrace_state) {
    printf("Make sure tce_init_backtracer() is called before calling print_stack_trace()\n");
    abort();
  }
  backtrace_full((struct backtrace_state *)__tce_backtrace_state, 0, tce_backtrace_callback, tce_backtrace_error_callback,
                 NULL);
}

#define N_SIGNALS 7

static void tce_signal_handler_callback(int signum) {
  printf("Error signal %s caught!\n", strsignal(signum));
  tce_print_backtrace();
  _exit(signum);
}

void tce_register_signal_handlers() {
  // Program Error Signals
  // https://www.gnu.org/software/libc/manual/html_node/Program-Error-Signals.html
  int signals_to_backtrace[N_SIGNALS] = {SIGFPE, SIGILL, SIGSEGV, SIGBUS, SIGABRT, SIGTRAP, SIGSYS};

  // Blocking signals with set
  sigset_t block_mask;
  sigemptyset(&block_mask);
  sigprocmask(SIG_BLOCK, &block_mask, NULL);
  for (size_t i = 0; i < N_SIGNALS; i++) {
    sigaddset(&block_mask, signals_to_backtrace[i]);
  }

  struct sigaction sigHandler;
  memset(&sigHandler, 0, sizeof(sigHandler));
  sigHandler.sa_handler = tce_signal_handler_callback;
  sigHandler.sa_mask = block_mask;
  sigHandler.sa_flags = 0;
  for (size_t i = 0; i < N_SIGNALS; i++) {
    sigaction(signals_to_backtrace[i], &sigHandler, NULL);
  }
}
