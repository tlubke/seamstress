#include <pthread.h>
#include <assert.h>
#include <signal.h>
#include <stdbool.h>
#include <stdlib.h>
#include <search.h>
#include <stdio.h>

#include "events.h"
#include "event_types.h"
#include "spindle.h"

struct ev_node {
  struct ev_node *next;
  struct ev_node *prev;
  union event_data *ev;
};

struct ev_queue {
  struct ev_node *head;
  struct ev_node *tail;
  ssize_t size;
  pthread_cond_t nonempty;
  pthread_mutex_t lock;
};

struct ev_queue queue;
bool quit;

static void handle_event(union event_data *ev);
static void ev_queue_push(union event_data *ev) {
  struct ev_node *event_node = calloc(1, sizeof(struct ev_node));
  event_node->ev = ev;
  if (queue.size == 0) {
    insque(event_node, NULL);
    queue.head = event_node;
  } else {
    insque(event_node, queue.tail);
  }
  queue.tail = event_node;
  queue.size += 1;
}
static union event_data *ev_queue_pop() {
  struct ev_node *event_node = queue.head;
  if (event_node == NULL) {
    return NULL;
  }
  union event_data *ev = event_node->ev;
  queue.head = event_node->next;
  if (event_node == queue.tail) {
    assert(queue.size == 1);
    queue.tail = NULL;
  }
  remque(event_node);
  free(event_node);
  queue.size -= 1;
  return ev;
}

void handle_signal(int i) {
  event_post(event_data_new(EVENT_QUIT));
}

void events_init(void) {
  queue.size = 0;
  queue.head = NULL;
  queue.tail = NULL;
  pthread_cond_init(&queue.nonempty, NULL);
}

void event_loop(void) {
  signal(SIGINT, handle_signal);
  union event_data *ev;
  while (!quit) {
    pthread_mutex_lock(&queue.lock);
    while (queue.size == 0) {
      pthread_cond_wait(&queue.nonempty, &queue.lock);
    }
    assert(queue.size > 0);
    ev = ev_queue_pop();
    pthread_mutex_unlock(&queue.lock);
    if (ev != NULL) {
      handle_event(ev);
    }
  }
}

union event_data *event_data_new(event_t evcode) {
  union event_data *ev = calloc(1, sizeof(union event_data));
  ev->type = evcode;
  return ev;
}

void event_data_free(union event_data *ev) {
  switch (ev->type) {
    case EVENT_EXEC_CODE_LINE:
      free(ev->exec_code_line.line);
      break;
    case EVENT_OSC:
      free(ev->osc_event.path);
      free(ev->osc_event.from_host);
      free(ev->osc_event.from_port);
      lo_message_free(ev->osc_event.msg);
      break;
  }
  free(ev);
}

void event_post(union event_data *ev) {
  assert(ev != NULL);
  pthread_mutex_lock(&queue.lock);
  if (queue.size == 0) {
    pthread_cond_signal(&queue.nonempty);
  }
  ev_queue_push(ev);
  pthread_mutex_unlock(&queue.lock);
}

void event_handle_pending(void) {
  union event_data *ev = NULL;
  char done = 0;
  while (!done) {
    pthread_mutex_lock(&queue.lock);
    if (queue.size > 0) {
      ev = ev_queue_pop();
    } else {
      done = 1;
      ev = NULL;
    }
    pthread_mutex_unlock(&queue.lock);
    if (ev != NULL) {
      handle_event(ev);
    }
  }
}

static void handle_event(union event_data *ev) {
  switch (ev->type) {
    case EVENT_EXEC_CODE_LINE:
      s_handle_exec_code_line(ev->exec_code_line.line);
      break;
    case EVENT_OSC:
      s_handle_osc_event(ev->osc_event.from_host, ev->osc_event.from_port, ev->osc_event.path, ev->osc_event.msg);
      break;
    case EVENT_QUIT:
      quit = true;
      break;
    case EVENT_RESET_LVM:
      s_reset_lvm();
      break;
  }
  event_data_free(ev);
}
