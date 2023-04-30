grid = require 'core/grid'
arc = require 'core/arc'
osc = require 'core/osc'
util = require 'lib/util'

init = function () end

_seamstress.monome = {
  add = function (id, dev_type, port)
    if not dev_type then return end
    if string.find(dev_type, "arc") then
      arc.new(id, tostring(port))
    else
      grid.new(id, tostring(port))
    end
    _seamstress.osc_send({"localhost", tostring(port)}, "/sys/info", {"localhost", tonumber(_seamstress.local_port)})
  end,
  remove = function (id)
    if arc.find[id] then
      arc.remove(id)
    else
      grid.remove(id)
    end
  end,
  handler = function (path, args, from)
    if path == "/sys/port" then
      _seamstress.osc_send(from, "/sys/port", {tonumber(_seamstress.local_port)})
    elseif path == "/sys/prefix" then
      _seamstress.osc_send(from, "/sys/prefix", {"/monome"})
    elseif path == "/sys/size" then
      if grid.ports[from[2]] then
        grid.ports[from[2]].rows = args[1]
        grid.ports[from[2]].cols = args[2]
      end
    end
  end
}

_startup = function (script_file)
  require(script_file)
  _seamstress.osc_send({"localhost", "12002"}, "/serialosc/list", {"localhost", tonumber(_seamstress.local_port)})
  _seamstress.osc_send({"localhost", "12002"}, "/serialosc/notify", {"localhost", tonumber(_seamstress.local_port)})
  init()
end
