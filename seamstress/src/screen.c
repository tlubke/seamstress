#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include "SDL2/SDL_error.h"
#include "SDL2/SDL_render.h"
#include "SDL2/SDL_surface.h"
#include "SDL2/SDL_video.h"
#include "event_types.h"
#include "events.h"
#include "screen.h"
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

static pthread_t thread;

static SDL_Window *window;
static SDL_Renderer *render;
static TTF_Font *font;

static int WIDTH = 256;
static int HEIGHT = 128;
static int ZOOM = 4;

void screen_redraw() {
  SDL_RenderPresent(render);
}

void screen_clear() {
  SDL_SetRenderDrawColor(render, 0, 0, 0, 255);
  SDL_RenderClear(render);
}

void screen_color(int r, int g, int b, int a) {
  SDL_SetRenderDrawColor(render, r, g, b, a);
}

void screen_pixel(int x, int y) {
  SDL_RenderDrawPoint(render, x, y);
}

void screen_line(int ax, int ay, int bx, int by) {
  SDL_RenderDrawLine(render, ax, ay, bx, by);
}

void screen_rect(int x, int y, int w, int h) {
  SDL_Rect r;
  r.x = x;
  r.y = y;
  r.w = w;
  r.h = h;
  SDL_RenderDrawRect(render, &r);
}

void screen_rect_fill(int x, int y, int w, int h) {
  SDL_Rect r;
  r.x = x;
  r.y = y;
  r.w = w;
  r.h = h;
  SDL_RenderFillRect(render, &r);
}

void screen_text(int x, int y, const char *text) {
  uint8_t r, g, b, a;
  SDL_Color col;
  SDL_GetRenderDrawColor(render, &r, &g, &b, &a);
  col.r = r;
  col.g = g;
  col.b = b;
  col.a = a;
  SDL_Surface *text_surf = TTF_RenderText_Solid(font, text, col);
  SDL_Texture *texture = SDL_CreateTextureFromSurface(render, text_surf);
  SDL_Rect rect;
  rect.x = x;
  rect.y = y;
  rect.w = text_surf->w;
  rect.h = text_surf->h;
  SDL_RenderCopy(render, texture, NULL, &rect);
  SDL_DestroyTexture(texture);
  SDL_FreeSurface(text_surf);
}

static void window_rect() {
  int xsize, ysize, xzoom, yzoom;
  SDL_GetWindowSize(window, &xsize, &ysize);
  for (xzoom = 1; ((1 + xzoom) * WIDTH) <= xsize; xzoom++);
  for (yzoom = 1; ((1 + yzoom) * HEIGHT) <= ysize; yzoom++);
  ZOOM = xzoom < yzoom ? xzoom : yzoom;
  SDL_RenderSetScale(render, ZOOM, ZOOM);
}

static void *screen_loop(void *x);

void screen_init(int x, int y) {
  WIDTH = x;
  HEIGHT = y;

  if (SDL_Init(SDL_INIT_VIDEO) < 0) {
    fprintf(stderr, "screen_init: %s\n", SDL_GetError());
    return;
  }

  if (TTF_Init() < 0) {
    fprintf(stderr, "screen_init: %s\n", TTF_GetError());
    return;
  }

  font = TTF_OpenFont("/usr/local/share/seamstress/resources/04b03.ttf", 8);
  if (!font) {
    fprintf(stderr, "screen_init: %s\n", TTF_GetError());
    return;
  }
  
  window = SDL_CreateWindow("seamstress",
                            SDL_WINDOWPOS_UNDEFINED,
                            SDL_WINDOWPOS_UNDEFINED,
                            WIDTH * ZOOM,
                            HEIGHT * ZOOM,
                            SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE );
  if (window == NULL) {
    fprintf(stderr, "screen_init: %s\n", SDL_GetError());
    return;
  }

  render = SDL_CreateRenderer(window, 0, 0);

  if (render == NULL) {
    fprintf(stderr, "screen_init: %s\n", SDL_GetError());
    return;
  }
  
  SDL_SetWindowMinimumSize(window, WIDTH, HEIGHT);
  window_rect();
  screen_clear();

  if (pthread_create(&thread, NULL, screen_loop, 0)) {
    fprintf(stderr, "screen_init: failed to create thread.\n");
  }
}

void screen_check(void) {
  union event_data *ev;
  SDL_Event event;
  while (SDL_PollEvent(&event) != 0) {
    switch(event.type) {
    case SDL_KEYDOWN:
      ev = event_data_new(EVENT_KEY);
      ev->key.scancode = event.key.keysym.sym;
      event_post(ev);
      break;
    case SDL_QUIT:
      ev = event_data_new(EVENT_QUIT);
      event_post(ev);
      break;
    case SDL_WINDOWEVENT:
      if (event.window.event == SDL_WINDOWEVENT_EXPOSED) {
        screen_redraw();
      }
      if (event.window.event == SDL_WINDOWEVENT_RESIZED) {
        window_rect();
        screen_redraw();
      }
      break;
    default:
      break;
    }
  }
}

void screen_deinit(void) {
  pthread_cancel(thread);
  TTF_CloseFont(font);
  SDL_DestroyRenderer(render);
  SDL_DestroyWindow(window);
  window = NULL;
  render = NULL;
  TTF_Quit();
  SDL_Quit();
}

void *screen_loop(void *x) {
  (void)x;
  union event_data *ev;
  struct timespec time;
  time.tv_nsec = 2000000;
  time.tv_sec = 0;
  while (1) {
    ev = event_data_new(EVENT_SCREEN_CHECK);
    event_post(ev);
    nanosleep(&time, NULL);
  }
}
