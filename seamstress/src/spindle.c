#include <stdio.h>
#include <stdlib.h>
#include "args.h"
#include "event_types.h"
#include "lua_interp.h"
#include "osc.h"
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

void s_handle_exec_code_line(char *line) {
  handle_line(lvm, line);
}
