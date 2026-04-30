local gears = require("gears")
local sysfs = require("continuity.sysinfo.temp.backends.sysfs")

---@class TempState
---@field zones  table<string, number>  Degrees Celsius keyed by sysfs path (e.g. "/sys/.../thermal_zone0/temp")
---@field avg    number                 Arithmetic mean across all zones in degrees Celsius

---@class TempBackend
---@field start fun(self, cb: fun(state: TempState))
---@field stop  fun(self)

---@class TempOptions
---@field backend? TempBackend  The backend to provide memory monitoring, defaults to sysfs backend.

local _state = nil ---@type TempState|nil
local _subscribers = {}
local _backend = nil
local _setup_called = false

local function _on_update(data)
	_state = data
	for _, sub in ipairs(_subscribers) do
		sub(_state)
	end
end

local temp = {}

--- Initiate temp monitoring.
---@param opts? TempOptions
function temp.setup(opts)
	if _setup_called then
		gears.debug.print_warning("sysinfo.temp: setup() called more than once; ignoring")
		return
	end
	_setup_called = true
	opts = opts or {}
	_backend = opts.backend or sysfs()
	_backend:start(_on_update)
end

--- Subscribe to receive temp state updates as available.
---@param fn fun(state: TempState) Callback to receive updates.
---@return fun()                   Unsubscribe function.
function temp:subscribe(fn)
	_subscribers[#_subscribers + 1] = fn
	if _state ~= nil then
		fn(_state)
	end
	return function()
		for i, sub in ipairs(_subscribers) do
			if sub == fn then
				table.remove(_subscribers, i)
				return
			end
		end
	end
end

--- Get the temp state if available.
---@return TempState|nil
function temp.state()
	return _state
end

function temp.stop()
	if _backend then
		_backend:stop()
		_backend = nil
	end
	_subscribers = {}
	_state = nil
	_setup_called = false
end

return temp
