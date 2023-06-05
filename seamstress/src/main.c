#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include "args.h"
#include "events.h"
#include "metro.h"
#include "osc.h"
#include "screen.h"
#include "spindle.h"
#include "input.h"
#include "device/device_monitor.h"

void print_version(void);

void cleanup(void) {
  metros_deinit();
  screen_deinit();
  dev_monitor_deinit();
  osc_deinit();
  s_deinit();
  fprintf(stderr, "seamstress shutdown complete\n");
  printf("Bye!\n");
  exit(0);
}

int main(int argc, char **argv) {
  args_parse(argc, argv);
  print_version();

  fprintf(stderr, "starting event handler\n");
  events_init();
  metros_init();

  fprintf(stderr, "starting spindle\n");
  s_init();

  fprintf(stderr, "starting device monitor\n");
  dev_monitor_init();

  atexit(cleanup);

  fprintf(stderr, "starting osc\n");
  osc_init();

  fprintf(stderr, "starting input\n");
  input_init();

  fprintf(stderr, "starting screen\n");
  screen_init(args_width(), args_height());

  fprintf(stderr, "spinning spindle\n");
  s_startup();

  fprintf(stderr, "starting main loop\n");
  event_handle_pending();
  event_loop();
}

void print_version(void) {
  printf("SEAMSTRESS\n");
  printf("seamstress version: %d.%d.%d\n", VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH);
}
