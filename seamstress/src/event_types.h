#pragma once
#include "osc.h"
#include <stdint.h>

typedef enum {
  EVENT_QUIT,
  EVENT_EXEC_CODE_LINE,
  EVENT_OSC,
  EVENT_RESET_LVM
} event_t;

struct event_common {
  uint32_t type;
};

struct event_exec_code_line {
  struct event_common common;
  char *line;
};

struct event_osc {
  struct event_common common;
  char *path;
  char *from_host;
  char *from_port;
  lo_message msg;
};

union event_data {
  uint32_t type;
  struct event_exec_code_line exec_code_line;
  struct event_osc osc_event;
};
