local Grid = {}
Grid.__index = Grid

Grid.find = {}
Grid.ports = {}

function Grid.new(id, port)
  if Grid.find[id] or Grid.ports[port] then return end

  local g = setmetatable({}, Grid)

  g.id = id
  g.port = port
  g.key = nil
  g.tilt = nil
  g.disconnect = nil
  g.rows = 8
  g.cols = 16

  g.state = {
    dirty = {false, false, false, false},
    {}, {}, {}, {}
  }

  for i = 1, 4 do
    for j = 1, 64 do
      g.state[i][j] = 0
    end
  end

  Grid.find[id] = g
  Grid.ports[port] = g
  Grid.add(g)
end

function Grid.add(dev)
  print("grid added:", dev.id, dev.port)
  if dev.connect then
    dev:connect()
  end
end

function Grid.remove(id)
  local grid = Grid.find[id]
  if not grid then return end
  local port = grid.port
  if grid.disconnect then
    grid.disconnect()
  end
  Grid.find[id] = nil
  Grid.ports[port] = nil
end

function Grid:rotation(val)
  _seamstress.osc_end({"localhost", self.port}, "/sys/rotation", {val})
end

local function x_y_to_quad(x, y)
  local quad = (((y - 1) // 8) << 1) + ((x - 1) // 8)
  x = (x - 1) % 8 + 1
  y = (x - 1) % 8
  local pos = 8 * y + x
  return quad, pos
end

function Grid:led(x, y, val)
  local quad, pos = x_y_to_quad(x, y)
  self.state[quad][pos] = val
  self.state.dirty[quad] = true
end

function Grid:all(val)
  local quads = x_y_to_quad(self.cols, self.rows)
  for i = 1, quads do
    for j = 1, 64 do
      self.state[i][j] = val
    end
    self.state.dirty[i] = true
  end
end

function Grid:refresh()
  for i = 1, 4 do
    if self.state.dirty[i] then
      _seamstress.osc_send({"localhost", self.port}, "/grid/level/map",
        {i - 1, table.unpack(self.state[i])})
      self.state.dirty[i] = false
    end
  end
end

function Grid:intensity(i)
  _seamstress.osc_send({"localhost", self.port}, "/sys/intensity", {i})
end

function Grid.connect(dev) end

_seamstress.grid = {
  key = function (port, x, y, z)
    local g = Grid.ports[port]
    if g ~= nil then
      if g.key ~= nil then
        g.key(x+1, y+1, z)
      end
    else
      error('no entry for grid at port ' .. port)
    end
  end,
  tilt = function (port, sensor, x, y, z)
    local g = Grid.ports[port]
    if g ~= nil then
      g.tilt(sensor+1, x, y, z)
    else
      error('no entry for grid at port ' .. port)
    end
  end
}

return Grid
