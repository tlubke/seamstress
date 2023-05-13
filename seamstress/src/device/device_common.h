#pragma once

#include <stdint.h>
#include <pthread.h>

typedef enum {
  DEV_TYPE_MONOME = 0,
  DEV_TYPE_COUNT,
  DEV_TYPE_INVALID
} device_t;

struct dev_common {
  device_t type;
  uint32_t id;
  pthread_t tid;
  char *path;
  char *serial;
  char *name;
  void *(*start)(void *self);
  void (*deinit)(void *self);
};
