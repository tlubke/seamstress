# dear Emacs, this is -*- python -*-

top = '.'
out = '.'

from waflib.Configure import conf

def options(ctx):
    ctx.load('compiler_c')

def configure(ctx):
    ctx.load('compiler_c')
    ctx.find_program('zig', var='ZIG', mandatory=False)

    if ctx.env.DEST_OS == 'darwin':
        ctx.env.INCLUDES_LUA = ['/opt/homebrew/include', '/usr/local/include']
        ctx.env.LIB_LUA = 'lua'
        ctx.env.LIBPATH_LUA = ['/opt/homebrew/lib', '/usr/local/lib']
        ctx.env.LDFLAGS_LUA = '-llua'
        
        ctx.env.INCLUDES_LO = '/opt/homebrew/include'
        ctx.env.LIB_LO = 'lo'
        ctx.env.LIBPATH_LO = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_LO = '-llo'

        ctx.env.INCLUDES_MONOME = '/opt/homebrew/include'
        ctx.env.LIB_MONOME = 'monome'
        ctx.env.LIBPATH_MONOME = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_MONOME = '-lmonome'

        ctx.env.INCLUDES_SDL = '/opt/homebrew/include'
        ctx.env.LIB_SDL = 'SDL2'
        ctx.env.LIBPATH_SDL = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_SDL = '-lSDL2' 

        ctx.env.INCLUDES_SDLTTF = '/opt/homebrew/include'
        ctx.env.LIB_SDLTTF = 'SDL2_ttf'
        ctx.env.LIBPATH_SDLTTF = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_SDLTTF = '-lSDL2_ttf'

    ctx.check_cc(
        define_name = "HAVE_LUA",
        mandatory = True,
        quote = 0,
        lib = "lua",
        use = "LUA",
        uselib_store = "LUA",
        msg = "Checking for lua"
    )
    ctx.check_cc(
        define_name = "HAVE_SDL",
        mandatory = True,
        quote = 0,
        lib = "SDL2",
        use = "SDL",
        uselib_store = "SDL",
        msg = "Checking for sdl"
    )
    ctx.check_cc(
        define_name = "HAVE_SDLTTF",
        mandatory = True,
        quote = 0,
        lib = "SDL2_ttf",
        use = "SDLTTF",
        uselib_store = "SDLTTF",
        msg = "Checking for sdl_ttf"
    )
    ctx.check_cc(
        define_name = "HAVE_LO",
        mandatory = True,
        quote = 0,
        lib = "lo",
        use = "LO",
        uselib_store = "LO",
        msg = "Checking for lo"
    )
    ctx.check_cc(
        define_name = "HAVE_MONOME",
        mandatory = True,
        quote = 0,
        lib = "monome",
        use = "MONOME",
        uselib_store = "MONOME",
        msg = "Checking for libmonome"
    )
    return

def build(ctx):
    ctx(rule='${ZIG} build -Doptimize=ReleaseFast')
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
