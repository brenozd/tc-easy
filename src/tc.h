#ifndef INCLUDE_SRC_TC_H_
#define INCLUDE_SRC_TC_H_

#include <stdbool.h>

bool tce_add_tbf(char dev[]);
bool tce_add_netem(char dev[], float delay_ms, float delay_correlation_pct, float jitter_ms, float loss_pct, bool replace);

#endif  // INCLUDE_SRC_TC_H_
