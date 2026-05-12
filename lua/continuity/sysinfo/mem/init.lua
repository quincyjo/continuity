local gears = require("gears")
local procmeminfo = require("continuity.sysinfo.mem.backends.procmeminfo")

---@class MemState
---@field total      integer  Mebibytes total
---@field used       integer  Mebibytes used (total - free - buffers - cached - sreclaimable)
---@field free       integer  Mebibytes free
---@field buffers    integer  Mebibytes in kernel buffers
---@field cached     integer  Mebibytes in page cache
---@field perc       number   Used divided by total times 100
---@field swap_total integer  Mebibytes swap total
---@field swap_used  integer  Mebibytes swap used
---@field swap_free  integer  Mebibytes swap free

---@class MemBackend
---@field start fun(self, cb: fun(state: MemState))
---@field stop  fun(self)

---@class MemOptions
---@field backend? MemBackend  The backend to provide memory monitoring, defaults to sysfs backend.

local _subscribers = {}
local _backend = nil
local _setup_called = false

local mem = {}

---@type MemState|nil
mem.state = nil

local function _on_update(data)
	mem.state = data
	for _, sub in ipairs(_subscribers) do
		sub(mem.state)
	end
end

--- Initiate memory monitoring.
---@param opts? MemOptions
function mem.setup(opts)
	if _setup_called then
		gears.debug.print_warning("sysinfo.mem: setup() called more than once; ignoring")
		return
	end
	_setup_called = true
	opts = opts or {}
	_backend = opts.backend or procmeminfo()
	_backend:start(_on_update)
end

--- Subscribe to receive memory state updates as available.
---@param fn fun(state: MemState)  Callback to receive updates.
---@return fun()                   Unsubscribe function.
function mem:subscribe(fn)
	_subscribers[#_subscribers + 1] = fn
	if mem.state ~= nil then
		fn(mem.state)
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

--- Stop memory monitoring.
function mem.stop()
	if _backend then
		_backend:stop()
		_backend = nil
	end
	_subscribers = {}
	mem.state = nil
	_setup_called = false
end

---@type Monitor<MemState>
return mem
