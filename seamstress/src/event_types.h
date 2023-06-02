#pragma once
#include "osc.h"
#include <stdint.h>

typedef enum {
  EVENT_QUIT,
  EVENT_EXEC_CODE_LINE,
  EVENT_OSC,
  EVENT_RESET_LVM,
  EVENT_MONOME_ADD,
  EVENT_MONOME_REMOVE,
  EVENT_GRID_KEY,
  EVENT_GRID_TILT,
  EVENT_ARC_ENCODER,
  EVENT_ARC_KEY,
  EVENT_KEY,
  EVENT_SCREEN_CHECK,
  EVENT_METRO,
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
  char *from_host;
  char *from_port;
  char *path;
  lo_message msg;
};

struct event_monome_add {
  struct event_common common;
  void *dev;
};

struct event_monome_remove {
  struct event_common common;
  uint32_t id;
};

struct event_grid_key {
    struct event_common common;
    uint8_t id;
    uint8_t x;
    uint8_t y;
    uint8_t state;
};

struct event_grid_tilt {
    struct event_common common;
    uint8_t id;
    uint8_t sensor;
    uint8_t x;
    uint8_t y;
    uint8_t z;
};

struct event_arc_encoder_delta {
    struct event_common common;
    uint8_t id;
    uint8_t number;
    int8_t delta;
};

struct event_arc_encoder_key {
    struct event_common common;
    uint8_t id;
    uint8_t number;
    int8_t state;
};

struct event_key {
  struct event_common common;
  uint16_t scancode;
};

struct event_metro {
  struct event_common common;
  int id;
  int stage;
};

union event_data {
  uint32_t type;
  struct event_exec_code_line exec_code_line;
  struct event_osc osc_event;
  struct event_monome_add monome_add;
  struct event_monome_remove monome_remove;
  struct event_grid_key grid_key;
  struct event_grid_tilt grid_tilt;
  struct event_arc_encoder_delta arc_encoder_delta;
  struct event_arc_encoder_key arc_encoder_key;
  struct event_key key;
  struct event_metro metro;
};
