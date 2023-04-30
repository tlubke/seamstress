# vim: ft=python

top = '.'
out = 'build'

def options(ctx):
    ctx.load('compiler_c')
    ctx.load('compiler_cxx')

def configure(ctx):
    ctx.load('compiler_cxx')
    ctx.load('compiler_c')
    ctx.load('clang_compilation_database')

    ctx.define('VERSION_MAJOR', 0)
    ctx.define('VERSION_MINOR', 0)
    ctx.define('VERSION_PATCH', 1)
    return

def build(ctx):
    ctx.recurse('seamstress')
    start_dir = ctx.path.find_dir('lua')
    ctx.install_files('${PREFIX}/share/seamstress/lua',
                      start_dir.ant_glob('**/*.lua'),
                      cwd=start_dir, relative_trick=True)
    return
