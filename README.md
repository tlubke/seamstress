# seamstress

seamstress is a Lua scripting environment for monome devices and OSC communication.

currently very much alpha software.

## installation

requires `liblo`. on macOS do

```
brew install liblo
```

to build, invoke

```
./waf configure
./waf
sudo ./waf install
```

## usage

invoke `seamstress` from the terminal.
`Ctrl+C` should exit, but at the time of this writing may lag.
by default seamstress looks for and runs a file called `script.lua`
in either the current directory or in `~/seamstress/`.
this behavior can be overridden, see `seamstress -h` for details.

## acknowledgments

seamstress is inspired by [monome norns's](https://github.com/monome/norns) matron,
which was written by @catfact.
norns was initiated by @tehn.
