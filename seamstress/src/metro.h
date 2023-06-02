#pragma once

extern const int NUM_METROS;

extern void metros_init(void);
extern void metros_deinit(void);
extern void metro_start(int idx, double seconds, int count, int stage);
extern void metro_stop(int idx);
extern void metro_set_time(int idx, double seconds);
