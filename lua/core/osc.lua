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

_seamstress.osc = {}

function _seamstress.osc.event(path, args, from)
  if OSC.event ~= nil then
    OSC.event(path, args, from)
  end
end

return OSC
