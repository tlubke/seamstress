local Arc = {}
Arc.__index = Arc

Arc.find = {}
Arc.ports = {}

function Arc.new(id, port)
  if Arc.find[id] or Arc.ports[port] then return end

  local a = setmetatable({}, Arc)

  a.id = id
  a.port = port
  a.delta = function (n, d) end
  a.key = function (n, z) end
  a.disconnect = function () end
  a.state = {
    dirty = {false, false, false, false},
    {}, {}, {}, {}
  }

  for i = 1,4 do
    for j = 1, 64 do
      a.state[i][j] = 0
    end
  end

  Arc.find[id] = a
  Arc.ports[port] = a
  Arc.add(a)
end

function Arc.add(dev)
  print('arc added:', dev.id, dev.port)
  if dev.connect then
    dev:connect()
  end
end

function Arc.connect(dev) end

function Arc.remove(id)
  local arc = Arc.find[id]
  if not arc then return end
  local port = arc.port
  if arc.disconnect then
    arc.disconnect()
  end
  Arc.find[id] = nil
  Arc.ports[port] = nil
end

function Arc:led(ring, x, val)
  self.state[ring][x] = val
  self.state.dirty[ring] = true
end

function Arc:all(ring, val)
  for j = 1,64 do
    self.state[ring][j] = val
  end
  self.state.dirty[ring] = true
end

function Arc:refresh()
  for i = 1, 4 do
    if self.state.dirty[i] then
      _seamstress.osc_send({"localhost", self.port}, "/monome/ring/map",
        {i - 1, table.unpack(self.state[i])})
      self.state.dirty[i] = false
    end
  end
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

_seamstress.arc = {
  delta = function (port, n, delta)
    local a = Arc.ports[port]
    if a ~= nil then
      if a.delta then
        a.delta(n+1, delta)
      end
    else
      error('no entry for arc at port ' .. port)
    end
  end,

  key = function (port, n, z)
    local a = Arc.ports[port]
    if a ~= nil then
      if a.key then
        a.key(n+1, z)
      end
    else
      error('no entry for arc at port ' .. port)
    end
  end
}

return Arc
