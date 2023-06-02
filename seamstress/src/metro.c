#include "metro.h"
#include "event_types.h"
#include "events.h"
#include <assert.h>
#include <pthread.h>
#include <limits.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define MAX_NUM_METROS 36
#define NSEC_PER_SEC 1000000000

enum {
  METRO_STATUS_RUNNING,
  METRO_STATUS_STOPPED
};

const int NUM_METROS = MAX_NUM_METROS;

struct metro {
  int idx;
  int status;
  double seconds;
  uint64_t count;
  uint64_t stage;
  uint64_t time;
  uint64_t delta;
  pthread_t tid;
  pthread_mutex_t stage_lock;
  pthread_mutex_t status_lock;
};

struct metro metros[MAX_NUM_METROS];

static void metro_handle_error(int code, const char *msg) {
  fprintf(stderr, "error code: %d (%s) in \"%s\"\n", code, strerror(code), msg);
}

static void metro_reset(struct metro *t, int stage);
static void metro_init(struct metro *t, uint64_t nsec, int count);
static void metro_cancel(struct metro *t);
static void *metro_thread_loop(void *metro);
static void metro_set_current_time(struct metro *t);
static void metro_sleep(struct metro *t);
static void metro_bang(struct metro *t);

void metros_init(void) {
  for (int i = 0; i < MAX_NUM_METROS; i++) {
    metros[i].status = METRO_STATUS_STOPPED;
    metros[i].seconds = 1.0;
  }
}

void metros_deinit(void) {
  for (int i = 0; i < MAX_NUM_METROS; i++) {
    metro_stop(i);
  }
}

void metro_start(int idx, double seconds, int count, int stage) {
  uint64_t nsec;

  if ((idx < 0) || (idx >= MAX_NUM_METROS)) {
    fprintf(stderr, "metro_start(): invalid metro index; not added. max count of metros is %d\n", MAX_NUM_METROS);
    return;
  }

  struct metro *t = &metros[idx];
  pthread_mutex_lock(&(t->status_lock));
  if (t->status == METRO_STATUS_RUNNING) {
    metro_cancel(t);
  }
  pthread_mutex_unlock(&(t->status_lock));
  if (seconds > 0.0) {
    metros[idx].seconds = seconds;
  }
  nsec = (uint64_t)(metros[idx].seconds * NSEC_PER_SEC);
  metros[idx].idx = idx;
  metro_reset(&metros[idx], stage);
  metro_init(&metros[idx], nsec, count);
}

void metro_stop(int idx) {
  if ((idx < 0) || (idx >= MAX_NUM_METROS)) {
    fprintf(stderr, "metro_stop(): invalid metro index, max count of metros is %d\n", MAX_NUM_METROS);
    return;
  }
  pthread_mutex_lock(&(metros[idx].status_lock));
  if (metros[idx].status != METRO_STATUS_STOPPED) {
    metro_cancel(&metros[idx]);
  }
  pthread_mutex_unlock(&(metros[idx].status_lock));
}

void metro_set_time(int idx, double seconds) {
  if ((idx < 0) || (idx >= MAX_NUM_METROS)) {
    return;
  }
  metros[idx].seconds = seconds;
  metros[idx].delta = (uint64_t)(seconds * NSEC_PER_SEC);
}

void metro_reset(struct metro *t, int stage) {
  pthread_mutex_lock(&(t->stage_lock));
  if (stage > 0) {
    t->stage = stage;
  } else {
    t->stage = 0;
  }
  pthread_mutex_unlock(&(t->stage_lock));
}

void metro_init(struct metro *t, uint64_t nsec, int count) {
  int res;
  pthread_attr_t attr;

  res = pthread_attr_init(&attr);
  if (res != 0) {
    metro_handle_error(res, "pthread_attr_init");
    return;
  }

  res = pthread_attr_setstacksize(&attr, PTHREAD_STACK_MIN);
  if (res != 0) {
    metro_handle_error(res, "pthread_attr_init");
    return;
  }
  res |= pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  if (res != 0) {
    metro_handle_error(res, "pthread_attr_init");
    return;
  }

  t->delta = nsec;
  t->count = count;
  res = pthread_create(&(t->tid), &attr, &metro_thread_loop, (void *)t);
  if (res != 0) {
    metro_handle_error(res, "pthread_create");
    return;
  }
  t->status = METRO_STATUS_RUNNING;
  if (res != 0) {
    metro_handle_error(res, "pthread_setschedparam");
    switch (res) {
    case ESRCH:
      fprintf(stderr, "specified thread does not exist\n");
      assert(false);
      break;
    case EINVAL:
      fprintf(stderr, "invalid thread policy value or associated parameter\n");
      assert(false);
      break;
    case EPERM:
      fprintf(stderr, "failed to set scheduling priority.\n");
      break;
    default:
      fprintf(stderr, "unknown error code\n");
      assert(false);
    }
    return;
  }
}

void *metro_thread_loop(void *metro) {
  struct metro *t = (struct metro *)metro;
  int stop = 0;

  pthread_mutex_lock(&(t->status_lock));
  t->status = METRO_STATUS_RUNNING;
  pthread_mutex_unlock(&(t->status_lock));

  metro_set_current_time(t);
  while (!stop) {
    metro_sleep(t);
    pthread_mutex_lock(&(t->stage_lock));
    if ((t->stage >= t->count) && (t->count > 0)) {
      stop = 1;
    }
    pthread_mutex_unlock(&(t->stage_lock));

    if (stop) {
      break;
    }
    pthread_testcancel();

    pthread_mutex_lock(&(t->stage_lock));
    metro_bang(t);
    t->stage += 1;
    pthread_mutex_unlock(&(t->stage_lock));
  }
  pthread_mutex_lock(&(t->status_lock));
  t->status = METRO_STATUS_STOPPED;
  pthread_mutex_unlock(&(t->status_lock));
  return NULL;
}

void metro_set_current_time(struct metro *t) {
  struct timespec time;
  clock_gettime(CLOCK_MONOTONIC, &time);
  t->time = (uint64_t)((NSEC_PER_SEC * (int64_t)time.tv_sec) + (int64_t)time.tv_nsec);
}

void metro_bang(struct metro *t) {
  union event_data *ev = event_data_new(EVENT_METRO);
  ev->metro.id = t->idx;
  ev->metro.stage = t->stage;
  event_post(ev);
}

#if __APPLE__
// from https://github.com/stanislaw/posix-macos-addons

void __timespec_diff(const struct timespec *lhs, const struct timespec *rhs, struct timespec *out) {
  assert(lhs->tv_sec <= rhs->tv_sec);

  out->tv_sec = rhs->tv_sec - lhs->tv_sec;
  out->tv_nsec = rhs->tv_nsec - lhs->tv_nsec;

  if (out->tv_sec < 0) {
    out->tv_sec = 0;
    out->tv_nsec = 0;
    return;
  }

  if (out->tv_nsec < 0) {
    if (out->tv_sec == 0) {
      out->tv_sec = 0;
      out->tv_nsec = 0;
      return;
    }

    out->tv_sec = out->tv_sec - 1;
    out->tv_nsec = out->tv_nsec + NSEC_PER_SEC;
  }
}
#endif

void metro_sleep(struct metro *t) {
  struct timespec ts;
  t->time += t->delta;
  ts.tv_sec = t->time / NSEC_PER_SEC;
  ts.tv_nsec = t->time % NSEC_PER_SEC;
#if __APPLE__
  struct timespec now, diff;
  clock_gettime(CLOCK_MONOTONIC, &now);
  __timespec_diff(&now, &ts, &diff);
  nanosleep(&diff, NULL);
#else
  clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL);
#endif
}

void metro_cancel(struct metro *t) {
  if (t->status == METRO_STATUS_STOPPED) {
    fprintf(stderr, "metro_cancel(): already stopped? shouldn't get here!\n");
    return;
  }
  int ret = pthread_cancel(t->tid);
  if (ret) {
    fprintf(stderr, "metro_stop(): pthread_cancel() failed; error: ");
    switch (ret) {
    case ESRCH:
      fprintf(stderr, "specified thread does not exist\n");
      break;
    default:
      fprintf(stderr, "unknown error code: %d\n", ret);
      assert(false);
    }
  } else {
    t->status = METRO_STATUS_STOPPED;
  }
}

#undef MAX_NUM_METROS
#undef NSEC_PER_SEC
