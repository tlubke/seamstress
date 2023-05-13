#include "device_monitor_macos.h"
#include "device_list.h"
#include "device_common.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitKeys.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOTypes.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
  IONotificationPortRef notify;
  io_iterator_t iter;
} notify_state_t;

static notify_state_t *state = NULL;
pthread_t watch_thread_id;

static void dev_add(const char *devnode);

static int wait_on_parent_usbdevice(io_service_t device) {
  io_registry_entry_t parent;

  for (;;) {
    if (IORegistryEntryGetParentEntry(device, kIOServicePlane, &parent)) {
      return 1;
    }
    device = parent;

    if (IOObjectConformsTo(device, kIOUSBDeviceClassName)) {
      break;
    }
  }

  IOServiceWaitQuiet(device, NULL);
  return 0;
}

static void iterate_devices(void *context, io_iterator_t iter) {
  (void)context;
  io_service_t device;
  io_struct_inband_t device_node;
  unsigned int len = 256;

  while ((device = IOIteratorNext(iter))) {
    IORegistryEntryGetProperty(device, kIODialinDeviceKey, device_node, &len);

    if (!wait_on_parent_usbdevice(device)) {
      dev_add(device_node);
    }
    IOObjectRelease(device);
  }
}

void dev_monitor_deinit(void) {
  IOObjectRelease(state->iter);
  IONotificationPortDestroy(state->notify);
}

static void *watch_loop(void *data) {
  (void)data;
  CFRunLoopRun();
  return NULL;
}

void dev_monitor_init(void) {
  state = calloc(1, sizeof(notify_state_t));
  
  CFMutableDictionaryRef matching;

  state->notify = IONotificationPortCreate((mach_port_t) 0);
  if (!(state->notify)) {
    fprintf(stderr, "dev_monitor_init(): couldn't allocate notification port!\n");
    return;
  }

  CFRunLoopAddSource(CFRunLoopGetCurrent(),
                     IONotificationPortGetRunLoopSource(state->notify),
                     kCFRunLoopDefaultMode);

  matching = IOServiceMatching(kIOSerialBSDServiceValue);
  CFDictionarySetValue(matching,
                       CFSTR(kIOSerialBSDTypeKey),
                       CFSTR(kIOSerialBSDAllTypes));

  IOServiceAddMatchingNotification(state->notify,
                                   kIOMatchedNotification,
                                   matching,
                                   iterate_devices,
                                   state,
                                   &state->iter);

  pthread_attr_t attr;
  int s = pthread_attr_init(&attr);
  if (s) {
    fprintf(stderr, "dev_monitor_init(): error initializing thread attributes\n");
  }
  s = pthread_create(&watch_thread_id, &attr, watch_loop, NULL);
  if (s) {
    fprintf(stderr, "dev_monitor_init(): error creating thread\n");
  }
  pthread_attr_destroy(&attr);
}

void dev_monitor_scan(void) {
  iterate_devices(state, state->iter);
}

// for now, a wrapper
void dev_add(const char *devnode) {
  if (devnode == NULL) {
    return;
  }
  dev_list_add(DEV_TYPE_MONOME, devnode, devnode);
}
