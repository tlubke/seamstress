local OSC = {}

OSC.__index = OSC

function OSC.event(path, args, from)
end

function OSC.send(to, path, args)
  if not to then
    to = {"localhost", _seamstress.remote_port}
  end
  _seamstress.osc_send(to, path, args)
end

_seamstress.serialosc = {}

function _seamstress.serialosc.handler(path, args, _)
  if path == "/serialosc/device" then
    local id, dev_type, port = table.unpack(args)
    _seamstress.monome.add(id, dev_type, port)
  elseif path == "/serialosc/add" then
    _seamstress.osc_send(
      {"localhost", "12002"},
      "/serialosc/list",
      {"localhost", tonumber(_seamstress.local_port)})
  elseif path == "/serialosc/remove" then
    local id = args[1]
    _seamstress.monome.remove(id)
  end
end

_seamstress.osc = {}

function _seamstress.osc.event(path, args, from)
  if string.find(path, "^/serialosc") then
    _seamstress.serialosc.handler(path, args, from)
  elseif string.find(path, "^/sys") then
    _seamstress.monome.handler(path, args, from)
  elseif string.find(path, "/enc/delta") then
    local ring, delta = table.unpack(args)
    _seamstress.arc.delta(from[2], ring, delta)
  elseif string.find(path, "/enc/key") then
    local ring, z = table.unpack(args)
    _seamstress.arc.key(from[2], ring, z)
  elseif string.find(path, "/grid/key") then
    local x, y, z = table.unpack(args)
    _seamstress.grid.key(from[2], x, y, z)
  elseif string.find(path, "/tilt") then
    local sensor, x, y, z = table.unpack(args)
    _seamstress.grid.tilt(from[2], sensor, x, y, z)
  end
  if OSC.event ~= nil then
    OSC.event(path, args, from)
  end
end

return OSC
