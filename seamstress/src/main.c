#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

#include "args.h"
#include "events.h"
#include "osc.h"
#include "spindle.h"

void print_version(void);

void cleanup(void) {
  osc_deinit();
  s_deinit();
  fprintf(stderr, "seamstress shutdown complete\n");
  printf("Bye!\n");
  exit(0);
}

int main(int argc, char **argv) {
  args_parse(argc, argv);
  print_version();
  events_init();
  s_init();
  atexit(cleanup);
  osc_init();
  s_startup();
  event_handle_pending();
  event_loop();
}

void print_version(void) {
  printf("SEAMSTRESS\n");
  printf("seamstress version: %d.%d.%d\n", VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH);
}
