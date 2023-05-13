#include "device.h"
#include "device_common.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#define TEST_NULl_AND_FREE(p) \
  if ((p) != NULL) {          \
    free(p);                  \
  }

static int dev_start(union dev *d);

union dev *dev_new(device_t type, const char *path, const char *name) {
  union dev *d = calloc(1, sizeof(union dev));

  if (d == NULL) {
    return NULL;
  }

  d->base.type = type;
  d->base.path = path ? strdup(path) : NULL;
  d->base.name = strdup(name);

  switch (type) {
  case DEV_TYPE_MONOME:
    if (dev_monome_init(d) < 0) {
      goto err_init;
    };
    break;
  default:
    fprintf(stderr, "calling dev_new() with unknown device type; this is an error!\n");
    goto err_init;
  }
  dev_start(d);
  return d;

 err_init:
  free(d);
  return NULL;
}

void dev_delete(union dev *d) {
  int ret;
  if (pthread_kill(d->base.tid, 0) == 0) {
    ret = pthread_cancel(d->base.tid);
    if (ret) {
      fprintf(stderr, "dev_delete(): error in pthread_cancel(): %d\n", ret);
      exit(EXIT_FAILURE);
    }
  }

  ret = pthread_join(d->base.tid, NULL);
  if (ret) {
    fprintf(stderr, "dev_delete(): error in pthread_join(): %d\n", ret);
    exit(EXIT_FAILURE);
  }

  d->base.deinit(d);

  TEST_NULl_AND_FREE(d->base.path);
  TEST_NULl_AND_FREE(d->base.serial);
  TEST_NULl_AND_FREE(d->base.name);

  free(d);
}

int dev_start(union dev *d) {
  pthread_attr_t attr;
  int ret;

  if (d->base.start == NULL) {
    return -1;
  }

  ret = pthread_attr_init(&attr);
  if (ret) {
    fprintf(stderr, "dev_start(): error on thread attributes\n");
    return -1;
  }
  ret = pthread_create(&d->base.tid, &attr, d->base.start, d);
  pthread_attr_destroy(&attr);
  if (ret) {
    fprintf(stderr, "dev_start(): error creating thread\n");
    return -1;
  }
  return 0;
}

int dev_id(union dev *d) {
  return d->base.id;
}

const char *dev_serial(union dev *d) {
  return d->base.serial;
}

const char *dev_name(union dev *d) {
  return d->base.name;
}
