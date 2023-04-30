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
