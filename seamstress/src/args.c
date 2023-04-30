#include "args.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#define ARG_BUF_SIZE 64

struct args {
  char script_file[ARG_BUF_SIZE];
  char local_port[ARG_BUF_SIZE];
  char remote_port[ARG_BUF_SIZE];
};

static struct args a = {
  .script_file = "script",
  .local_port = "7777",
  .remote_port = "6666",
};

int args_parse(int argc, char **argv) {
  int opt;
  while ((opt = getopt(argc, argv, "s:l:b")) != -1) {
    switch (opt) {
      case 's':
        strncpy(a.script_file, optarg, ARG_BUF_SIZE - 1);
        break;
      case 'l':
        strncpy(a.local_port, optarg, ARG_BUF_SIZE - 1);
      case 'b':
        strncpy(a.remote_port, optarg, ARG_BUF_SIZE -1);
        break;
      case '?':
      case 'h':
      default:
        fprintf(stdout, "Start seamstress with optional overrides:\n");
        fprintf(stdout, "-s   override user script [default %s]\n", a.script_file);
        fprintf(stdout, "-l   override OSC listen port [default %s]\n", a.local_port);
        fprintf(stdout, "-b   override OSC broadcast port [default %s]\n", a.remote_port);
        exit(1);
      ;
    }
  }
  return 0;
}

const char *args_local_port(void) {
  return a.local_port;
}

const char *args_remote_port(void) {
  return a.remote_port;
}

const char *args_script_file(void) {
  return a.script_file;
}
