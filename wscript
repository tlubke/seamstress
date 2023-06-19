# dear Emacs, this is -*- python -*-

top = '.'
out = '.'

from waflib.Configure import conf

def options(ctx):
    ctx.load('compiler_c')

def configure(ctx):
    ctx.load('compiler_c')
    ctx.find_program('zig')

    def linux_check_lua(lua_versions):
        for lua in lua_versions:
            if ctx.check_cfg(package=lua, args='--cflags --libs', \
                             uselib_store=lua, mandatory=False):
                ctx.env.deps.append(lua)
                return
        ctx.fatal('Could not find Lua')

    if ctx.env.DEST_OS == 'darwin':
        ctx.env.INCLUDES_RTMIDI = ['/opt/homebrew/include']
        ctx.env.LIB_RTMIDI = 'rtmidi'
        ctx.env.LIBPATH_RTMIDI = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_RTMIDI = '-lrtmidi'

        ctx.env.INCLUDES_LUA = ['/opt/homebrew/include', '/usr/local/include']
        ctx.env.LIB_LUA = 'lua'
        ctx.env.LIBPATH_LUA = ['/opt/homebrew/lib', '/usr/local/lib']
        ctx.env.LDFLAGS_LUA = '-llua'

        ctx.env.INCLUDES_LO = '/opt/homebrew/include'
        ctx.env.LIB_LO = 'lo'
        ctx.env.LIBPATH_LO = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_LO = '-llo'

        ctx.env.INCLUDES_SDL = '/opt/homebrew/include'
        ctx.env.LIB_SDL = 'SDL2'
        ctx.env.LIBPATH_SDL = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_SDL = '-lSDL2'

        ctx.env.INCLUDES_SDLTTF = '/opt/homebrew/include'
        ctx.env.LIB_SDLTTF = 'SDL2_ttf'
        ctx.env.LIBPATH_SDLTTF = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_SDLTTF = '-lSDL2_ttf'

    if ctx.env.DEST_OS == 'linux':
        linux_check_lua(['lua', 'lua5.4', 'lua5.3', 'lua5.2', 'lua5.1'])
    if ctx.env.DEST_OS == 'darwin':
        ctx.check_cc(
            mandatory = True,
            quote = 0,
            lib = "lua",
            use = "LUA",
            msg = "Checking for lua"
        )

    ctx.check_cc(
        mandatory = True,
        quote = 0,
        lib = "SDL2",
        use = "SDL",
        msg = "Checking for sdl"
    )
    ctx.check_cc(
        mandatory = True,
        quote = 0,
        lib = "SDL2_ttf",
        use = "SDLTTF",
        msg = "Checking for sdl_ttf"
    )
    ctx.check_cc(
        mandatory = True,
        quote = 0,
        lib = "lo",
        use = "LO",
        msg = "Checking for lo"
    )
    ctx.check_cc(
        mandatory = True,
        quote = 0,
        lib = "rtmidi",
        use = "RTMIDI",
        msg = "Checking for rtmidi"
    )
    return

def build(ctx):
    ctx(rule='${ZIG} build -Doptimize=ReleaseFast', always=True)
    start_dir = ctx.path.find_dir('lua')
    ctx.install_files('${PREFIX}/share/seamstress/lua',
                      start_dir.ant_glob('**/*.lua'),
                      cwd=start_dir, relative_trick=True)
    start_dir = ctx.path.find_dir('resources')
    ctx.install_files('${PREFIX}/share/seamstress/resources',
                      start_dir.ant_glob('*.ttf'),
                      cwd=start_dir, relative_trick=True)
    if ctx.is_install:
        ctx(rule='cp zig-out/bin/seamstress ${PREFIX}/bin/seamstress')
    return
