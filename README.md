# seamstress

seamstress is a Lua scripting environment for monome devices and OSC communication.

currently very much alpha software.

## installation

requires `liblo`, `lua` and `libmonome`. on macOS do

```
brew install lua liblo libmonome
```

to build, invoke

```
./waf configure
./waf
sudo ./waf install
```

## usage

invoke `seamstress` from the terminal.
`Ctrl+C` or 'quit' exits.
by default seamstress looks for and runs a file called `script.lua`
in either the current directory or in `~/seamstress/`.
this behavior can be overridden, see `seamstress -h` for details.

## acknowledgments

seamstress is inspired by [monome norns's](https://github.com/monome/norns) matron,
which was written by @catfact.
macOS device handling borrows from [serialosc](https://github.com/monome/serialosc),
written by @wrl.
norns was initiated by @tehn.
