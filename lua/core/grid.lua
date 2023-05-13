local vport = require 'vport'

local Grid = {}
Grid.__index = Grid

Grid.devices = {}
Grid.ports = {}

for i = 1, 4 do
	Grid.ports[i] = {
    name = "none",
    device = nil,
    delta = nil,
    key = nil,
    led = vport.wrap('led'),
    all = vport.wrap('all'),
    refresh = vport.wrap('refresh'),
    rotation = vport.wrap('rotation'),
    intensity = vport.wrap('intensity'),
    tilt_enable = vport.wrap('tilt_enable'),
    cols = 0,
    rows = 0
  }
end

function Grid.new(id, serial, name, dev)
  local g = setmetatable({}, Grid)

  g.id = id
  g.serial = serial
  g.name = name .. " " .. serial
  g.dev = dev
  g.key = nil
  g.tilt = nil
  g.remove = nil
  g.rows = _seamstress.grid_rows(dev)
  g.cols = _seamstress.grid_cols(dev)

  for i = 1, 4 do
    if Grid.ports[i].name == g.name then
      return g
    end
  end
  for i = 1, 4 do
    if Grid.ports[i].name == "none" then
      Grid.ports[i].name = g.name
      break
    end
  end

  return g
end


function Grid.add(dev)
  print("grid added:", dev.id, dev.name, dev.serial)
end

function Grid.connect(n)
	n = n or 1
  return Grid.ports[n]
end

function Grid.remove(dev) end

function Grid:rotation(val)
  _seamstress.grid_set_rotation(self.dev, val)
end

function Grid:led(x, y, val)
  _seamstress.grid_set_led(self.dev, x, y, val)
end

function Grid:all(val)
  _seamstress.grid_all_led(self.dev, val)
end

function Grid:refresh()
  _seamstress.monome_refresh(self.dev)
end

function Grid:intensity(i)
  _seamstress.monome_intensity(self.dev, i)
end

function Grid.update_devices()
	for _, device in pairs(Grid.devices) do
    device.port = nil
  end

  for i = 1, 4 do
    Grid.ports[i].device = nil
    for _, device in pairs(Grid.devices) do
      if device.name == Grid.ports[i].name then
        Grid.ports[i].device = device
        device.port = i
      end
    end
  end
end

_seamstress.grid = {
  add = function (id, serial, name, dev)
    local g = Grid.new(id, serial, name, dev)
    Grid.devices[id] = g
    Grid.update_devices()
    if Grid.add ~= nill then Grid.add(g) end
  end,
  
  remove = function (id)
    local g = Grid.devices[id]
    if g then
      if Grid.ports[g.port].remove then
        Grid.ports[g.port].remove()
      end
      if Grid.remove then
        Grid.remove(Grid.devices[id])
      end
    end
    Grid.devices[id] = nil
    Grid.update_devices()
  end,

  key = function (id, x, y, z)
    local grid = Grid.devices[id]
    if grid ~= nil then
      if grid.key then
        grid.key(x, y, z)
      end

      if grid.port then
        if Grid.ports[grid.port].key then
          Grid.ports[grid.port].key(x, y, z)
        end
      end
    else
      error('no entry for grid ' .. id)
    end
  end,

  tilt = function (id, sensor, x, y, z)
    local grid = Grid.devices[id]
    if grid ~= nil then
      if grid.tilt then
        grid.tilt(sensor, x, y, z)
      end
      if grid.port then
        if Grid.ports[grid.port].tilt then
          Grid.ports[grid.port].tilt(sensor, x, y, z)
        end
      end
    else
      error('no entry for grid ' .. id)
    end
  end
}

return Grid
