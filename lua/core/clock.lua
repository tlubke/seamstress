--- clock coroutines
-- @module clock

local clock = {}

_seamstress.clock = {}
_seamstress.clock.threads = {}
local clock_id_counter = 1
local function new_id()
	local id = clock_id_counter
  clock_id_counter = clock_id_counter + 1
  return id
end

--- create and start a coroutine.
-- @tparam function f coroutine functions
-- @param[opt] ... any extra arguments passed to f
-- @treturn integer coroutine id that can be used with clock.cancel
-- @see clock.cancel
function clock.run(f, ...)
	local co = coroutine.create(f)
  local id = new_id()
  _seamstress.clock.threads[id] = co
  _seamstress.clock_resume(id, co, ...)
  return id
end

--- stop a coroutine started by clock.run.
-- @tparam integer id coroutine id
-- @see clock.run
function clock.cancel(id)
	_seamstress.clock_cancel(id)
  _seamstress.clock.threads[id] = nil
end

local SCHEDULE_SLEEP = 0
local SCHEDULE_SYNC = 1
--- suspend coroutine and schedule resuming time.
-- call from *within* a coroutine function started by `clock.run`
-- @tparam float s seconds to wait for
function clock.sleep(...)
	return coroutine.yield(SCHEDULE_SLEEP, ...)
end

--- suspend coroutine and schedule resuming sync quantum.
-- call from *within* a coroutine function started by `clock.run`
-- @tparam float beat sync quantum (may be larger than 1)
-- @tparam[opt] float offset if set, this will be added to the sync quantum
function clock.sync(...)
	return coroutine.yield(SCHEDULE_SYNC, ...)
end

--- returns the current time in beats since reset was called.
-- @treturn number beats time in beats
function clock.get_beats()
	_seamstress.clock_get_beats()
end

--- returns the current tempo in bpm
-- @treturn number bpm
function clock.get_tempo()
  _seamstress.clock_get_tempo()
end

--- returns the length in seconds of a single beat
-- @treturn number seconds
function clock.get_beat_per_sec()
	local bpm = clock.get_tempo()
  return 60 / bpm
end

clock.transport = {
  --- callback when clock starts
  start = function() end,
  --- callback when the clock stops
  stop = function () end,
  --- callback when the clock beat number is reset
  reset = function() end,
}

_seamstress.transport = {
  start = function()
    if clock.transport.start then clock.transport.start() end
  end,
  stop = function ()
    if clock.transport.stop then clock.transport.stop() end
  end,
  reset = function ()
    if clock.transport.reset then clock.transport.reset() end
  end,
}

return clock
