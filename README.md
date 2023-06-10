# seamstress

seamstress is a Lua scripting environment for monome devices and OSC communication.

currently beta software.

## installation

requires `liblo`, `sdl2`, `sdl2_ttf`, `lua` and `libmonome`. on macOS do

```
brew install lua liblo libmonome sdl2 sdl2_ttf
```

building from source requires [zig](https://github.com/ziglang/zig).
download a binary from [here](https://ziglang.org/download/) and add it to your PATH.
without zig installed, the following commands will instead attempt
to install the provided binary (which is for M1 mac); 
worth a shot if one does not want to install zig,
but zig is not a big download.

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

## acknowledgments

seamstress is inspired by [monome norns's](https://github.com/monome/norns) matron,
which was written by @catfact.
macOS device handling borrows from [serialosc](https://github.com/monome/serialosc),
written by @wrl.
norns was initiated by @tehn.
