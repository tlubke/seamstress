--- random utils
-- @module util
local Util = {}

--- check whether a file exists
-- @tparam string name filename
-- @function util.exists
function Util.exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

--- round a number with optional quantization
-- @tparam number number a number
-- @tparam number quant quantization
-- @function util.round
function Util.round(number, quant)
  if quant == 0 then
    return number
  else
    return math.floor(number/(quant or 1) + 0.5) * (quant or 1)
  end
end

--- clear the terminal window
-- @function util.clear_screen
function Util.clear_screen()
  Util.os_capture("clear")
end

--- execute OS command
-- @tparam string cmd command to execute
-- @tparam[opt] bool raw flag whether to clean up output
-- @treturn string output from executing the command
-- @function util.os_capture
function Util.os_capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = string.gsub(s, '^%s+', '')
  s = string.gsub(s, '%s+$', '')
  s = string.gsub(s, '[\n\r]+', ' ')
end

return Util
