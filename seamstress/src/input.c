#include <stdbool.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "event_types.h"
#include "events.h"
#include "input.h"

static pthread_t pid;

#define RX_BUF_LEN 4096

static void *input_run(void *p) {
  (void)p;
  bool quit = false;
  char rxbuf[RX_BUF_LEN];
  int num_bytes;
  bool newline;
  char b;

  while (!quit) {
    num_bytes = 0;
      newline = false;
    while (!newline) {
      if (num_bytes < RX_BUF_LEN) {
        if (read(STDIN_FILENO, &b, 1) < 1) {
          fprintf(stderr, "failed to read from stdin!\n");
          return NULL;
        }
        if (b == '\0') {
          continue;
        }
        if ((b == '\n') || (b == '\r')) {
          newline = true;
        }
        rxbuf[num_bytes++] = b;
      }
    }
    if (!strcmp(rxbuf, "quit\n")) {
      event_post(event_data_new(EVENT_QUIT));
      quit = true;
      continue;
    }
    if (num_bytes > 0) {
      char *line = malloc((num_bytes + 1) * sizeof(char));
      strncpy(line, rxbuf, num_bytes);
      line[num_bytes] = '\0';
      union event_data *ev = event_data_new(EVENT_EXEC_CODE_LINE);
      ev->exec_code_line.line = line;
      event_post(ev);
    }
  }
  return NULL;
}

void input_init(void) {
  pthread_attr_t attr;
  int s;
  s = pthread_attr_init(&attr);
  if (s != 0) {
    fprintf(stderr, "input_init(): error in pthread_attr_init(): %d\n", s);
  }
  s = pthread_create(&pid, &attr, &input_run, NULL);
  if (s != 0) {
    fprintf(stderr, "input_init(): error in pthread_create(): %d\n", s);
  }
  pthread_attr_destroy(&attr);
}
