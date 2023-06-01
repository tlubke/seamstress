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
  char width[ARG_BUF_SIZE];
  char height[ARG_BUF_SIZE];
};

static struct args a = {
  .script_file = "script",
  .local_port = "7777",
  .remote_port = "6666",
  .width = "256",
  .height = "128",
};

int args_parse(int argc, char **argv) {
  int opt;
  while ((opt = getopt(argc, argv, "x:y:s:l:b:?:h")) != -1) {
    switch (opt) {
    case 'x':
      strncpy(a.width, optarg, ARG_BUF_SIZE - 1);
      break;
    case 'y':
      strncpy(a.height, optarg, ARG_BUF_SIZE - 1);
      break;
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
      fprintf(stdout, "-x   override window width [default %s]\n", a.width);
      fprintf(stdout, "-y   override window height [default %s]\n", a.height);
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

int args_width(void) {
  return atoi(a.width);
}

int args_height(void) {
  return atoi(a.height);
}
