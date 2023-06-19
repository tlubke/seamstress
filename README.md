# seamstress

seamstress is a Lua scripting environment for monome devices and OSC communication.

currently beta software.

## installation

requires `liblo`, `sdl2`, `sdl2_ttf`, `rtmidi`, and `lua`. on macOS do

```
brew install lua liblo rtmidi sdl2 sdl2_ttf
```

building from source requires the master build of [zig](https://github.com/ziglang/zig).
download a binary from [here](https://ziglang.org/download/) and add it to your PATH.
to build, invoke

```
git submodule update --init --recursive
./waf configure
./waf
sudo ./waf install
```

## usage

invoke `seamstress` from the terminal.
`Ctrl+C`, 'quit' or closing the OS window exits.
by default seamstress looks for and runs a file called `script.lua`
in either the current directory or in `~/seamstress/`.
this behavior can be overridden, see `seamstress -h` for details.

## docs

the lua API is documented [here](https://ryleealanza.org/assets/doc/index.html).
to regenerate docs, you'll need [LDoc](https://github.com/lunarmodules/ldoc),
which requires Penlight.
with both installed, running `ldoc .` in the base directory of seamstress will
regenerate documentation.

## acknowledgments

seamstress is inspired by [monome norns's](https://github.com/monome/norns) matron,
which was written by @catfact.
norns was initiated by @tehn.
