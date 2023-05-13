#pragma once

#include "device_common.h"
#include "device_monome.h"

union dev {
  struct dev_common base;
  struct dev_monome monome;
};

extern void devices_init(void);
extern union dev *dev_new(device_t type, const char *path, const char *name);

extern void dev_delete(union dev *d);
extern int dev_id(union dev *d);
extern const char *dev_serial(union dev *d);
extern const char *dev_name(union dev *d);
