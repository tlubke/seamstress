#pragma once

extern void screen_init(int x, int y);
extern void screen_deinit(void);
extern void screen_check(void);

extern void screen_redraw();
extern void screen_clear();
extern void screen_color(int r, int g, int b, int a);
extern void screen_pixel(int x, int y);
extern void screen_line(int ax, int ay, int bx, int by);
extern void screen_rect(int x, int y, int w, int h);
extern void screen_rect_fill(int x, int y, int w, int h);
extern void screen_text(int x, int y, const char *text);
