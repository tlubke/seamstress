#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "args.h"
#include "device/device_monome.h"
#include "event_types.h"
#include "lua_interp.h"
#include "metro.h"
#include "osc.h"
#include "screen.h"
#include "spindle.h"
#include "events.h"

// Lua
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#include <string.h>
#include <math.h>

static lua_State *lvm;

static int _osc_send(lua_State *l);
static int _reset_lvm(lua_State *l);

void s_run_code(const char *code) {
  dostring(lvm, code, "s_run_code");
  fflush(stdout);
}

static inline void _push_lua_func(const char *field, const char *func){
  lua_getglobal(lvm, "_seamstress");
  lua_getfield(lvm, -1, field);
  lua_remove(lvm, -2);
  lua_getfield(lvm, -1, func);
  lua_remove(lvm, -2);
}

static int _grid_set_led(lua_State *l);
static int _arc_set_led(lua_State *l);
static int _grid_all_led(lua_State *l);
static int _arc_all_led(lua_State *l);
static int _grid_set_rotation(lua_State *l);
static int _grid_tilt_enable(lua_State *l);
static int _grid_tilt_disable(lua_State *l);
static int _monome_refresh(lua_State *l);
static int _monome_intensity(lua_State *l);
static int _grid_rows(lua_State *l);
static int _grid_cols(lua_State *l);
static int _screen_redraw(lua_State *l);
static int _screen_pixel(lua_State *l);
static int _screen_line(lua_State *l);
static int _screen_rect(lua_State *l);
static int _screen_rect_fill(lua_State *l);
static int _screen_text(lua_State *l);
static int _screen_color(lua_State *l);
static int _screen_clear(lua_State *l);
static int _metro_start(lua_State *l);
static int _metro_stop(lua_State *l);
static int _metro_set_time(lua_State *l);

static inline void lua_register_seamstress(const char *name, int (*f)(lua_State *l)) {
  lua_pushcfunction(lvm, f);
  lua_setfield(lvm, -2, name);
}

void s_init(void) {
  fprintf(stderr, "starting lua vm\n");
  lvm = luaL_newstate();
  luaL_openlibs(lvm);

  lua_newtable(lvm);

  lua_register_seamstress("osc_send", &_osc_send);

  lua_register_seamstress("grid_set_led", &_grid_set_led);
  lua_register_seamstress("grid_all_led", &_grid_all_led);
  lua_register_seamstress("grid_rows", &_grid_rows);
  lua_register_seamstress("grid_cols", &_grid_cols);
  lua_register_seamstress("grid_set_rotation", &_grid_set_rotation);
  lua_register_seamstress("grid_tilt_enable", &_grid_tilt_enable);
  lua_register_seamstress("grid_tilt_disable", &_grid_tilt_disable);
  lua_register_seamstress("arc_set_led", &_arc_set_led);
  lua_register_seamstress("arc_all_led", &_arc_all_led);
  lua_register_seamstress("monome_refresh", &_monome_refresh);
  lua_register_seamstress("monome_intensity", &_monome_intensity);
  lua_register_seamstress("screen_redraw", &_screen_redraw);
  lua_register_seamstress("screen_pixel", &_screen_pixel);
  lua_register_seamstress("screen_line", &_screen_line);
  lua_register_seamstress("screen_rect", &_screen_rect);
  lua_register_seamstress("sreen_rect_fill", &_screen_rect_fill);
  lua_register_seamstress("screen_text", &_screen_text);
  lua_register_seamstress("screen_color", &_screen_color);
  lua_register_seamstress("screen_clear", &_screen_clear);
  lua_register_seamstress("metro_start", &_metro_start);
  lua_register_seamstress("metro_stop", &_metro_stop);
  lua_register_seamstress("metro_set_time", &_metro_set_time);

  lua_register_seamstress("reset_lvm", &_reset_lvm);

  lua_pushstring(lvm, args_local_port());
  lua_setfield(lvm, -2, "local_port");
  lua_pushstring(lvm, args_remote_port());
  lua_setfield(lvm, -2, "remote_port");

  lua_setglobal(lvm, "_seamstress");

  char *config = getenv("SEAMSTRESS_CONFIG");
  char cmd[256];

  if (config == NULL) {
    snprintf(cmd, 256, "dofile('/usr/local/share/seamstress/lua/config.lua')\n");
  } else {
    snprintf(cmd, 256, "dofile('%s')\n", config);
  }
  fprintf(stderr, "running lua config file: %s", cmd);
  s_run_code(cmd);
  s_run_code("require('core/seamstress')");
}

void s_startup(void) {
  lua_getglobal(lvm, "_startup");
  lua_pushstring(lvm, args_script_file());
  report(lvm, docall(lvm, 1, 0));
}

void s_deinit(void) {
  fprintf(stderr, "shutting down lua vm\n");
  lua_close(lvm);
}

void s_reset_lvm() {
  s_deinit();
  s_init();
  s_startup();
}

int _reset_lvm(lua_State *l) {
  lua_check_num_args(0);
  lua_settop(l, 0);
  event_post(event_data_new(EVENT_RESET_LVM));
  return 0;
}

int _grid_set_led(lua_State *l) {
  lua_check_num_args(4);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  int x = (int)luaL_checkinteger(l, 2) - 1;
  int y = (int)luaL_checkinteger(l, 3) - 1;
  int z = (int)luaL_checkinteger(l, 4);
  dev_monome_grid_set_led(md, x, y, z);
  lua_settop(l, 0);
  return 0;
}

int _arc_set_led(lua_State *l) {
  lua_check_num_args(4);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  int n = (int)luaL_checkinteger(l, 2) - 1;
  int x = (int)luaL_checkinteger(l, 3) - 1;
  int val = (int)luaL_checkinteger(l, 4);
  dev_monome_arc_set_led(md, n, x, val);
  lua_settop(l, 0);
  return 0;
}

int _grid_all_led(lua_State *l) {
  lua_check_num_args(2);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  int z = (int)luaL_checkinteger(l, 2);
  dev_monome_all_led(md, z);
  lua_settop(l, 0);
  return 0;
}

int _arc_all_led(lua_State *l) {
  return _grid_all_led(l);
}

int _grid_set_rotation(lua_State *l) {
  lua_check_num_args(2);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  int z = (int)luaL_checkinteger(l, 2);
  dev_monome_set_rotation(md, z);
  lua_settop(l, 0);
  return 0;
}

int _grid_tilt_enable(lua_State *l) {
  lua_check_num_args(2);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  int id = (int)luaL_checkinteger(l, 2) - 1;
  dev_monome_tilt_enable(md, id);
  lua_settop(l, 0);
  return 0;
}

int _grid_tilt_disable(lua_State *l) {
  lua_check_num_args(2);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  int id = (int)luaL_checkinteger(l, 2) - 1;
  dev_monome_tilt_disable(md, id);
  lua_settop(l, 0);
  return 0;
}

int _monome_refresh(lua_State *l) {
  lua_check_num_args(1);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  dev_monome_refresh(md);
  lua_settop(l, 0);
  return 0;
}

int _monome_intensity(lua_State *l) {
  lua_check_num_args(2);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  int i = (int)luaL_checkinteger(l, 2);
  dev_monome_intensity(md, i);
  lua_settop(l, 0);
  return 0;
}

int _grid_rows(lua_State *l) {
  lua_check_num_args(1);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  lua_pushinteger(l, dev_monome_grid_rows(md));
  return 1;
}

int _grid_cols(lua_State *l) {
  lua_check_num_args(1);
  luaL_checktype(l, 1, LUA_TLIGHTUSERDATA);
  struct dev_monome *md = lua_touserdata(l, 1);
  lua_pushinteger(l, dev_monome_grid_cols(md));
  return 1;
}

int _screen_redraw(lua_State *l) {
  lua_check_num_args(0);
  screen_redraw();
  return 0;
}

int _screen_clear(lua_State *l) {
  lua_check_num_args(0);
  screen_clear();
  return 0;
}

int _screen_color(lua_State *l) {
  lua_check_num_args(4);
  int r = (int)luaL_checkinteger(l, 1);
  int g = (int)luaL_checkinteger(l, 2);
  int b = (int)luaL_checkinteger(l, 3);
  int a = (int)luaL_checkinteger(l, 4);
  screen_color(r, g, b, a);
  lua_settop(l, 0);
  return 0;
}

int _screen_pixel(lua_State *l) {
  lua_check_num_args(2);
  int x = (int)luaL_checkinteger(l, 1) - 1;
  int y = (int)luaL_checkinteger(l, 2) - 1;
  screen_pixel(x, y);
  lua_settop(l, 0);
  return 0;
}

int _screen_line(lua_State *l) {
  lua_check_num_args(4);
  int ax = (int)luaL_checkinteger(l, 1) - 1;
  int ay = (int)luaL_checkinteger(l, 2) - 1;
  int bx = (int)luaL_checkinteger(l, 3) - 1;
  int by = (int)luaL_checkinteger(l, 4) - 1;
  screen_line(ax, ay, bx, by);
  lua_settop(l, 0);
  return 0;
}

int _screen_rect(lua_State *l) {
  lua_check_num_args(4);
  int x = (int)luaL_checkinteger(l, 1) - 1;
  int y = (int)luaL_checkinteger(l, 2) - 1;
  int w = (int)luaL_checkinteger(l, 3);
  int h = (int)luaL_checkinteger(l, 4);
  screen_rect(x, y, w, h);
  lua_settop(l, 0);
  return 0;
}

int _screen_rect_fill(lua_State *l) {
  lua_check_num_args(4);
  int x = (int)luaL_checkinteger(l, 1) - 1;
  int y = (int)luaL_checkinteger(l, 2) - 1;
  int w = (int)luaL_checkinteger(l, 3);
  int h = (int)luaL_checkinteger(l, 4);
  screen_rect_fill(x, y, w, h);
  lua_settop(l, 0);
  return 0;
}

int _screen_text(lua_State *l) {
  lua_check_num_args(3);
  int x = (int)luaL_checkinteger(l, 1) - 1;
  int y = (int)luaL_checkinteger(l, 2) - 1;
  const char *text = lua_tostring(l, 3);
  screen_text(x, y, text);
  lua_settop(l, 0);
  return 0;
}

int _osc_send(lua_State *l) {
  const char *host = NULL;
  const char *port = NULL;
  const char *path = NULL;
  lo_message msg;

  int num_args = lua_gettop(l);

  luaL_checktype(l, 1, LUA_TTABLE);

  if (lua_rawlen(l, 1) != 2) {
    luaL_argerror(l, 1, "address should be a table in the form {host, port}");
  }

  lua_pushnumber(l, 1);
  lua_gettable(l, 1);
  if (lua_isstring(l, -1)) {
    host = lua_tostring(l, -1);
  } else {
    luaL_argerror(l, 1, "address should be a table in the form {host, port}");
  }
  lua_pop(l, 1);

  lua_pushnumber(l, 2);
  lua_gettable(l, 1);
  if (lua_isstring(l, -1)) {
    port = lua_tostring(l, -1);
  } else {
    luaL_argerror(l, 1, "address should be a table in the form {host, port}");
  }
  lua_pop(l, 1);

  luaL_checktype(l, 2, LUA_TSTRING);
  path = lua_tostring(l, 2);

  if ((host == NULL) || (port == NULL) || (path == NULL)) {
    return 1;
  }

  msg = lo_message_new();

  if (num_args > 2) {
    luaL_checktype(l, 3, LUA_TTABLE);
    for (size_t i = 1; i <= lua_rawlen(l, 3); i++) {
      lua_pushnumber(l, i);
      lua_gettable(l, 3);
      int argtype = lua_type(l, -1);

      switch (argtype) {
        case LUA_TNIL:
          lo_message_add_nil(msg);
          break;
        case LUA_TNUMBER:
          lo_message_add_float(msg, lua_tonumber(l, -1));
          break;
        case LUA_TBOOLEAN:
          if (lua_toboolean(l, -1)) {
            lo_message_add_true(msg);
          } else {
            lo_message_add_false(msg);
          }
          break;
        case LUA_TSTRING:
          lo_message_add_string(msg, lua_tostring(l, -1));
          break;
        default:
          lo_message_free(msg);
          luaL_error(l, "invalid osc argument type %s", lua_typename(l, argtype));
          break;
      }

      lua_pop(l, 1);
    }
  }
  osc_send(host, port, path, msg);
  lo_message_free(msg);
  lua_settop(l, 0);
  return 0;
}

int _metro_start(lua_State *l) {
  static int idx = 0;
  double seconds = -1.0;
  int count = -1;
  int stage = 0;
  int nargs = lua_gettop(l);

  if (nargs > 0) {
    idx = (int)luaL_checkinteger(l, 1) - 1;
  }
  if (nargs > 1) {
    seconds = (double)luaL_checknumber(l, 2);
  }
  if (nargs > 2) {
    count = (int)luaL_checkinteger(l, 3);
  }
  if (nargs > 3) {
    stage = (int)luaL_checkinteger(l, 4) - 1;
  }

  metro_start(idx, seconds, count, stage);
  lua_settop(l, 0);
  return 0;
}

int _metro_stop(lua_State *l) {
  lua_check_num_args(1);
  int idx = (int)luaL_checkinteger(l, 1) - 1;
  metro_stop(idx);
  lua_settop(l, 0);
  return 0;
}

int _metro_set_time(lua_State *l) {
  lua_check_num_args(2);
  int idx = (int)luaL_checkinteger(l, 1) - 1;
  double sec = (double)luaL_checknumber(l, 2);
  metro_set_time(idx, sec);
  lua_settop(l, 0);
  return 0;
}

void s_handle_osc_event(char *from_host, char *from_port, char *path, lo_message msg) {
  const char *types = NULL;
  int argc;
  lo_arg **argv = NULL;

  types = lo_message_get_types(msg);
  argc = lo_message_get_argc(msg);
  argv = lo_message_get_argv(msg);

  _push_lua_func("osc", "event");

  lua_pushstring(lvm, path);
  lua_createtable(lvm, argc, 0);
  for (int i = 0; i < argc; i++) {
    switch (types[i]) {
      case LO_INT32:
        lua_pushinteger(lvm, argv[i]->i);
        break;
      case LO_FLOAT:
        lua_pushnumber(lvm, argv[i]->f);
        break;
      case LO_STRING:
        lua_pushstring(lvm, &argv[i]->s);
        break;
      case LO_BLOB:
        lua_pushlstring(lvm, lo_blob_dataptr((lo_blob)argv[i]), lo_blob_datasize((lo_blob)argv[i]));
        break;
      case LO_INT64:
        lua_pushinteger(lvm, argv[i]->h);
        break;
      case LO_DOUBLE:
        lua_pushnumber(lvm, argv[i]->d);
        break;
      case LO_SYMBOL:
        lua_pushstring(lvm, &argv[i]->S);
        break;
      case LO_MIDI:
        lua_pushlstring(lvm, (const char *)&argv[i]->m, 4);
        break;
      case LO_TRUE:
        lua_pushboolean(lvm, 1);
        break;
      case LO_FALSE:
        lua_pushboolean(lvm, 0);
        break;
      case LO_NIL:
        lua_pushnil(lvm);
        break;
      case LO_INFINITUM:
        lua_pushnumber(lvm, INFINITY);
        break;
      default:
        fprintf(stderr, "unknown osc typetag: %c\n", types[i]);
        lua_pushnil(lvm);
        break;
    }
    lua_rawseti(lvm, -2, i + 1);
  }

  lua_createtable(lvm, 2, 0);
  lua_pushstring(lvm, from_host);
  lua_rawseti(lvm, -2, 1);
  lua_pushstring(lvm, from_port);
  lua_rawseti(lvm, -2, 2);

  report(lvm, docall(lvm, 3, 0));
}

void s_handle_screen_key(u_int16_t scancode) {
  _push_lua_func("screen", "key");
  lua_pushinteger(lvm, scancode);
  report(lvm, docall(lvm, 1,0));
}

void s_handle_exec_code_line(char *line) {
  handle_line(lvm, line);
}

void s_handle_monome_add(void *dev) {
  struct dev_monome *md = (struct dev_monome *)dev;
  int id = md->dev.id;
  const char *serial = md->dev.serial;
  const char *name = md->dev.name;
  _push_lua_func("monome", "add");
  lua_pushinteger(lvm, id + 1);
  lua_pushstring(lvm, serial);
  lua_pushstring(lvm, name);
  lua_pushlightuserdata(lvm, dev);
  report(lvm, docall(lvm, 4, 0));
}

void s_handle_monome_remove(int id) {
  _push_lua_func("monome", "remove");
  lua_pushinteger(lvm, id + 1);
  report(lvm, docall(lvm, 1, 0));
}

void s_handle_grid_key(int id, int x, int y, int state) {
  _push_lua_func("grid", "key");
  lua_pushinteger(lvm, id + 1);
  lua_pushinteger(lvm, x + 1);
  lua_pushinteger(lvm, y + 1);
  lua_pushinteger(lvm, state > 0);
  report(lvm, docall(lvm, 4, 0));
}

void s_handle_grid_tilt(int id, int sensor, int x, int y, int z) {
  _push_lua_func("grid", "tilt");
  lua_pushinteger(lvm, id + 1);
  lua_pushinteger(lvm, sensor + 1);
  lua_pushinteger(lvm, x + 1);
  lua_pushinteger(lvm, y + 1);
  lua_pushinteger(lvm, z + 1);
  report(lvm, docall(lvm, 5, 0));
}

void s_handle_arc_encoder(int id, int number, int delta) {
  _push_lua_func("arc", "delta");
  lua_pushinteger(lvm, id + 1);
  lua_pushinteger(lvm, number + 1);
  lua_pushinteger(lvm, delta);
  report(lvm, docall(lvm, 3, 0));
}

void s_handle_arc_key(int id, int number, int state) {
  _push_lua_func("arc", "key");
  lua_pushinteger(lvm, id + 1);
  lua_pushinteger(lvm, number + 1);
  lua_pushinteger(lvm, state > 0);
  report(lvm, docall(lvm, 3, 0));
}

void s_handle_metro(const int idx, const int stage) {
  lua_getglobal(lvm, "_seamstress");
  lua_getfield(lvm, -1, "metro");
  lua_remove(lvm, -2);
  lua_pushinteger(lvm, idx + 1);
  lua_pushinteger(lvm, stage + 1);
  report(lvm, docall(lvm, 2, 0));
}
