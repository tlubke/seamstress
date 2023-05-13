grid = require 'core/grid'
arc = require 'core/arc'
osc = require 'core/osc'
util = require 'lib/util'

init = function () end

_seamstress.monome = {
  add = function (id, serial, name, dev)
    if string.find(name, "monome arc") then
      _seamstress.arc.add(id, serial, name, dev)
    else
      _seamstress.grid.add(id, serial, name, dev)
    end
  end,
  remove = function (id)
    if arc.devices[id] then
      _seamstress.arc.remove(id)
    else
      _seamstress.grid.remove(id)
    end
  end,
}

_startup = function (script_file)
  require(script_file)
  init()
end
