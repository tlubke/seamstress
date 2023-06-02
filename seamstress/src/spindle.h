#pragma once
#include <stdint.h>
#include "osc.h"

// start/stop lua
extern void s_init(void);
extern void s_startup(void);
extern void s_deinit(void);
extern void s_reset_lvm(void);

extern void s_handle_exec_code_line(char *line);
extern void s_handle_osc_event(char *from_host, char *from_port, char *path, lo_message msg);
extern void s_handle_monome_add(void *dev);
extern void s_handle_monome_remove(int id);
extern void s_handle_grid_key(int id, int x, int y, int state);
extern void s_handle_grid_tilt(int id, int sensor, int x, int y, int z);
extern void s_handle_arc_encoder(int id, int number, int delta);
extern void s_handle_arc_key(int id, int number, int state);
extern void s_handle_screen_key(uint16_t scancode);
extern void s_handle_metro(const int idx, const int stage);
