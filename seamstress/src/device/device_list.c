#include "device.h"
#include "device_common.h"
#include "../events.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <search.h>

static int id = 0;

struct dev_node {
  struct dev_node *next;
  struct dev_node *prev;
  union dev *d;
};

struct dev_q {
  struct dev_node *head;
  struct dev_node *tail;
  size_t size;
};

struct dev_q device_queue;

static struct dev_node *dev_lookup_path(const char *path, struct dev_node *node_head){
  const char *node_path;

  if (path == NULL) {
    return NULL;
  }

  if (node_head == NULL) {
    node_head = device_queue.head;
  }

  while (node_head != NULL) {
    node_path = node_head->d->base.path;
    if (node_path != NULL && strcmp(path, node_path) == 0) {
      return node_head;
    }
    node_head = node_head->next;
  }
  return NULL;
}

void dev_list_init(void) {
  device_queue.size = 0;
  device_queue.head = NULL;
  device_queue.tail = NULL;
}

union event_data *post_add_event(union dev *d, event_t event_type) { 
  if (d == NULL) {
    fprintf(stderr, "dev_list_add: error allocating device data\n");
    return NULL;
  }

  struct dev_node *dn = calloc(1, sizeof(struct dev_node));

  if (dn == NULL) {
    fprintf(stderr, "dev_list_add: error allocating device queue node\n");
    free(d);
    return NULL;
  }

  d->base.id = id++;
  dn->d = d;
  insque(dn, device_queue.tail);
  device_queue.tail = dn;
  if (device_queue.size == 0) {
    device_queue.head = dn;
  }
  device_queue.size++;

  union event_data *ev;
  ev = event_data_new(event_type);
  return ev;
}

void dev_list_add(device_t type, const char *path, const char *name) {
  if (type < 0) {
    return;
  }

  union event_data *ev = NULL;
  union dev *d;
  switch(type) {
  case DEV_TYPE_MONOME:
    d = dev_new(type, path, name);
    ev = post_add_event(d, EVENT_MONOME_ADD);
    break;
  default:
    fprintf(stderr, "dev_list_add(): error posting event (unknown type)\n");
  }
  if (ev != NULL) {
    ev->monome_add.dev = d;
    event_post(ev);
  }
}

static void dev_list_remove_node(struct dev_node *dn, union event_data *event_remove) {
  event_post(event_remove);

  if (device_queue.head == dn) {
    device_queue.head = dn->next;
  }
  if (device_queue.tail == dn) {
    device_queue.tail = dn->prev;
  }
  remque(dn);
  device_queue.size--;

  dev_delete(dn->d);
  free(dn);
}

void dev_list_remove(device_t type, const char *node) {
  struct dev_node *dn = dev_lookup_path(node, NULL);
  if (dn == NULL) {
    return;
  }
  union event_data *ev;

  switch (type) {
  case DEV_TYPE_MONOME:
    ev = event_data_new(EVENT_MONOME_REMOVE);
    ev->monome_remove.id = dn->d->base.id;
    break;
  default:
    fprintf(stderr, "dev_list_remove(): error posting event (unknown type)\n");
    return;
  }
  dev_list_remove_node(dn, ev);
}
