#pragma once

#include "lauxlib.h"
#include <lua.h>

#define NUM_TO_STRING(n) #n
#define LUA_ARG_ERROR(n) "error: requires " NUM_TO_STRING(n) " arguments"
#define lua_check_num_args(n)               \
  if (lua_gettop(l) != n) {                 \
    return luaL_error(l, LUA_ARG_ERROR(n)); \
  }

extern int docall(lua_State *L, int narg, int nres);

extern int dostring(lua_State *L, const char *string, const char *name);

extern int report(lua_State *L, int status);

extern int handle_line(lua_State *L, char *line);
