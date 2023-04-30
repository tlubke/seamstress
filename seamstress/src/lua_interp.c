/*
** $Id: lua.c,v 1.228 2016/12/13 15:50:58 roberto Exp roberto $
** Lua stand-alone interpreter
** See Copyright Notice in lua.h
*
* modified by ezra buchla ( @catfact ) 2017
* redacted by rylee lyman ( @ryleelyman ) 2023
*/
#include "lua_interp.h"
#include "lauxlib.h"
#include "lua.h"
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static lua_State *globalL = NULL;

#define STATUS_INCOMPLETE 999

static char *saveBuf = NULL;
static int saveBufLen = 0;
static int continuing = 0;

static void save_statement_buffer(char *buf) {
  saveBufLen = strlen(buf);
  saveBuf = realloc(saveBuf, saveBufLen + 1);
  strcpy(saveBuf, buf);
  continuing = 1;
}

static void clear_statement_buffer(void) {
  free(saveBuf);
  saveBufLen = 0;
  saveBuf = NULL;
  continuing = 0;
}

static int message_handler(lua_State *L) {
  const char *msg = lua_tostring(L, 1);
  if (msg == NULL) {
    if (luaL_callmeta(L, 1, "__tostring") && (lua_type(L, -1) == LUA_TSTRING)) {
      return 1;
    }
    else {
      msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
    }
  }
  luaL_traceback(L, L, msg, 1);
  return 1;
}

static void lua_stop(lua_State *L, lua_Debug *ar) {
  lua_sethook(L, NULL, 0, 0);
  luaL_error(L, "interrupted!");
}

static void lua_action(int i) {
  lua_sethook(globalL, lua_stop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

static int dochunk(lua_State *L, int status) {
  if (status == LUA_OK) {
    status = docall(L, 0, 0);
  }
  return report(L, status);
}

int docall(lua_State *L, int narg, int nres) {
  int status;
  int base = lua_gettop(L) - narg;
  lua_pushcfunction(L, message_handler);
  lua_insert(L, base);
  globalL = L;
  status = lua_pcall(L, narg, nres, base);
  lua_remove(L, base);

  return status;
}

int dostring(lua_State *L, const char *str, const char *name) {
  return dochunk(L, luaL_loadbuffer(L, str, strlen(str), name));
}

int report(lua_State *L, int status) {
  if (status != LUA_OK) {
    const char *msg = lua_tostring(L, -1);
    lua_writestringerror("%s\n", msg);
    lua_pop(L, 1);
  }
  return status;
}

static int add_return(lua_State *L) {
  const char *line = lua_tostring(L, -1);
  const char *retline = lua_pushfstring(L, "return %s;", line);
  int status = luaL_loadbuffer(L, retline, strlen(retline), "=stdin");
  if (status == LUA_OK) {
    lua_remove(L, -2);
    lua_remove(L, -2);
  } else{
    lua_pop(L, 2);
  }
  return status;
}

#define EOFMARK "<eof>"
#define marklen (sizeof(EOFMARK) / sizeof(char) - 1)

static int incomplete(lua_State *L, int status) {
  if (status == LUA_ERRSYNTAX) {
    size_t length;
    const char *msg = lua_tolstring(L, -1, &length);
    if ((length >= marklen) && (strcmp(msg + length - marklen, EOFMARK) == 0)) {
      lua_pop(L, 1);
      return 1;
    }
  }
  return 0;
}

static int try_statement(lua_State *L) {
  size_t len;
  int status;
  char *line = (char *)lua_tolstring(L, 1, &len);
  char *buf;

  if (continuing) {
    buf = malloc(saveBufLen + 1 + strlen(line) + 1);
    sprintf(buf, "%s\n%s", saveBuf, line);
    len += saveBufLen + 1;
  } else {
    buf = line;
  }
  status = luaL_loadbuffer(L, buf, len, "=stdin");

  if (incomplete(L, status)) {
    status = STATUS_INCOMPLETE;
    save_statement_buffer(buf);
  } else {
    clear_statement_buffer();
    lua_remove(L, -2);
  }
  return status;
}

static void lua_print(lua_State *L) {
  int n = lua_gettop(L);
  if (n > 0) {
    luaL_checkstack(L, LUA_MINSTACK, "too many results to print");
    lua_getglobal(L, "print");
    lua_insert(L, 1);
    if (lua_pcall(L, n, 0, 0) != LUA_OK) {
      lua_writestringerror("error calling 'print' (%s)\n", lua_tostring(L, -1));
    }
    fflush(stdout);
  }
}


int handle_line(lua_State *L, char *line) {
  size_t length;
  int status;
  lua_settop(L, 0);
  length = strlen(line);
  if ((length > 0) && (line[length - 1] == '\n')) {
    line[--length] = '\0';
  }

  lua_pushlstring(L, line, length);
  status = add_return(L);
  if (status == LUA_OK) {
    goto call;
  }
  status = try_statement(L);
  if (status == LUA_OK) {
    goto call;
  }
  if (status == STATUS_INCOMPLETE) {
    fprintf(stderr, "<incomplete>\n");
    goto exit;
  }

call:
  status = docall(L, 0, LUA_MULTRET);
  if (status == LUA_OK) {
    if (lua_gettop(L) == 0) {
      fprintf(stderr, "<ok>\n");
    }
    lua_print(L);
    fprintf(stderr, "\n");
  } else {
    report(L, status);
  }
exit:
  lua_settop(L, 0);
  return 0;
}

