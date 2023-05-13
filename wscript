# dear Emacs, this is -*- python -*-

top = '.'
out = 'build'

def options(ctx):
    ctx.load('compiler_c')
    ctx.load('compiler_cxx')

def configure(ctx):
    ctx.load('compiler_cxx')
    ctx.load('compiler_c')
    ctx.load('clang_compilation_database')

    if ctx.env.DEST_OS == 'darwin':
        ctx.env.INCLUDES_LO = '/opt/homebrew/include'
        ctx.env.LIB_LO = 'lo'
        ctx.env.LIBPATH_LO = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_LO = '-llo'

        ctx.env.INCLUDES_MONOME = '/opt/homebrew/include'
        ctx.env.LIB_MONOME = 'monome'
        ctx.env.LIBPATH_MONOME = '/opt/homebrew/lib'
        ctx.env.LDFLAGS_MONOME = '-lmonome'

    ctx.check_cc(
        define_name = "HAVE_LUA",
        mandatory = True,
        quote = 0,
        lib = "lua",
        uselib_store = "LUA",
        msg = "Checking for lua"
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

    ctx.define('VERSION_MAJOR', 0)
    ctx.define('VERSION_MINOR', 1)
    ctx.define('VERSION_PATCH', 0)
    return

def build(ctx):
    ctx.recurse('seamstress')
    start_dir = ctx.path.find_dir('lua')
    ctx.install_files('${PREFIX}/share/seamstress/lua',
                      start_dir.ant_glob('**/*.lua'),
                      cwd=start_dir, relative_trick=True)
    return
