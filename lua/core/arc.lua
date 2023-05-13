local vport = require 'vport'

local Arc = {}
Arc.__index = Arc

Arc.devices = {}
Arc.ports = {}

for i = 1, 4 do
  Arc.ports[i] = {
    name = "none",
    device = nil,
    delta = nil,
    key = nil,
    led = vport.wrap('led'),
    all = vport.wrap('all'),
    refresh = vport.wrap('refresh'),
    segment = vport.wrap('segment'),
  }
end

function Arc.new(id, serial, name, dev)
  local a = setmetatable({}, Arc)

  a.id = id
  a.serial = serial
  a.name = name .. " " .. serial
  a.dev = dev
  a.delta = nil
  a.key = nil
  a.remove = nil
  a.port = nil

  for i = 1, 4 do
    if Arc.ports[i].name == a.name then
      return a
    end
  end
  for i = 1, 4 do
    if Arc.ports[i].name == "none" then
      Arc.ports[i].name = a.name
      break
    end
  end

  return a
end

function Arc.add(dev)
  print('arc added:', dev.id, dev.name, dev.serial)
end

function Arc.connect(n)
  n = n or 1
  return Arc.ports[n]
end

function Arc.remove(dev) end

function Arc:led(ring, x, val)
  _seamstress.arc_set_led(self.dev, ring, x, val)
end

function Arc:all(val)
  _seamstress.arc_all_led(self.dev, val)
end

function Arc:refresh()
  _seamstress.monome_refresh(self.dev)
end

function Arc:segment(ring, from, to, level)
  local tau = 2 * math.pi

  local function overlap(a, b, c, d)
    if a > b then
      return overlap(a, tau, c, d) + overlap(0, b, c, d)
    elseif c > d then
      return overlap(a, b, c, tau) + overlap(a, b, 0, d)
    else
      return math.max(0, math.min(b,d) - math.max(a, c))
    end
  end

  local function overlap_segment(a, b, c, d)
    return overlap(a % tau, b % tau, c % tau, d % tau)
  end

  local leds = {}
  local step = tau / 64
  for i=1,64 do
    local a = tau / 64 * (i - 1)
    local b = tau / 64 * i
    local overlap_amt = overlap_segment(from, to, a, b)
    leds[i] = util.round(overlap_amt / step * level)
    self:led(ring, i, leds[i])
  end
end

function Arc.update_devices()
	for _, device in pairs(Arc.devices) do
    device.port = nil
  end

  for i = 1, 4 do
    Arc.ports[i].device = nil
    for _, device in pairs(Arc.devices) do
      if device.name == Arc.ports[i].name then
        Arc.ports[i].device = device
        device.port = i
      end
    end
  end
end

_seamstress.arc = {
  add = function (id, serial, name, dev)
    local a = Arc.new(id, serial, name, dev)
    Arc.devices[id] = a
    Arc.update_devices()
    if Arc.add ~= nil then Arc.add(a) end
  end,

  remove = function (id)
    local a = Arc.devices[id]
    if a then
      if Arc.ports[a.port].remove then
        Arc.ports[a.port].remove()
      end
      if Arc.remove then
        Arc.remove(Arc.devices[id])
      end
    end
    Arc.devices[id] = nil
    Arc.update_devices()
  end,

  delta = function (id, n, d)
    local arc = Arc.devices[id]
    if arc ~= nil then
      if arc.delta then
        arc.delta(n, d)
      end

      if arc.port then
        if Arc.ports[arc.port].delta then
          Arc.ports[arc.port].delta(n, d)
        end
      end
    else
      error('no entry for arc ' .. id)
    end
  end,

  key = function (id, n, z)
    local arc = Arc.devices[id]

    if arc ~= nil then
      if arc.key then
        arc.key(n, z)
      end
      if arc.port then
        if Arc.ports[arc.port].key then
          Arc.ports[arc.port].key(n, z)
        end
      end
    else
      error('no entry for arc ' .. id)
    end
  end
}

return Arc
