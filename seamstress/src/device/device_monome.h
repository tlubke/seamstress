#pragma once

#include <stdint.h>
#include <stdbool.h>

#include "device_common.h"
#include <monome.h>

typedef enum {
  DEVICE_MONOME_TYPE_GRID,
  DEVICE_MONOME_TYPE_ARC,
} device_monome_type_t;

struct dev_monome {
  struct dev_common dev;
  device_monome_type_t type;
  monome_t *m;
  uint8_t data[4][64];
  bool dirty[4];
  int cols;
  int rows;
  int quads;
};

extern void dev_monome_grid_set_led(struct dev_monome *md, uint8_t x, uint8_t y, uint8_t val);
extern void dev_monome_arc_set_led(struct dev_monome *md, uint8_t n, uint8_t x, uint8_t val);
extern void dev_monome_all_led(struct dev_monome *md, uint8_t val);
extern void dev_monome_set_quad(struct dev_monome *md, uint8_t quad, uint8_t *data);
extern void dev_monome_refresh(struct dev_monome *md);
extern int dev_monome_grid_rows(struct dev_monome *md);
extern int dev_monome_grid_cols(struct dev_monome *md);
extern void dev_monome_intensity(struct dev_monome *md, uint8_t intensity);
extern void dev_monome_set_rotation(struct dev_monome *md, uint8_t val);
extern void dev_monome_tilt_enable(struct dev_monome *md, uint8_t sensor);
extern void dev_monome_tilt_disable(struct dev_monome *md, uint8_t sensor);

extern int dev_monome_init(void *self);
extern void dev_monome_deinit(void *self);
extern void *dev_monome_start(void *self);
