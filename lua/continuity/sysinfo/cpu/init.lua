local gears = require("gears")
local procstat = require("continuity.sysinfo.cpu.backends.procstat")

---@class CpuCoreState
---@field usage   number  Percentage (0-100)
---@field user    number  Percentage in user space
---@field system  number  Percentage in kernel space
---@field idle    number  Percentage idle
---@field iowait  number  Percentage waiting on I/O
---@field steal   number  Percentage stolen (relevant in VMs)

---@class CpuState
---@field usage   number        Overall usage percentage across all cores
---@field user    number        Percentage in user space
---@field system  number        Percentage in kernel space
---@field idle    number        Percentage idle
---@field iowait  number        Percentage waiting on I/O
---@field steal   number        Percentage stolen (relevant in VMs)
---@field cores   CpuCoreState[]  Per-core breakdown, index 1 = core 0

---@class CpuBackend
---@field start fun(self, cb: fun(state: CpuState))
---@field stop  fun(self)

---@class CpuOptions
---@field backend? CpuBackend  The backend to provide CPU monitoring, defaults to procstat backend.

local _state = nil ---@type CpuState|nil
local _subscribers = {}
local _backend = nil
local _setup_called = false

local function _on_update(data)
	_state = data
	for _, sub in ipairs(_subscribers) do
		sub(_state)
	end
end

local cpu = {}

--- Initiates CPU monitoring.
---@param opts? CpuOptions
function cpu.setup(opts)
	if _setup_called then
		gears.debug.print_warning("sysinfo.cpu: setup() called more than once; ignoring")
		return
	end
	_setup_called = true
	opts = opts or {}
	_backend = opts.backend or procstat()
	_backend:start(_on_update)
end

--- Subscribe to receive CPU state updates as available.
---@param fn fun(state: CpuState)  Callback to receive updates.
---@return fun()                   Unsubscribe function.
function cpu:subscribe(fn)
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

--- Get the current state, if available.
---@return CpuState|nil
function cpu.state()
	return _state
end

--- Stop CPU monitoring.
function cpu.stop()
	if _backend then
		_backend:stop()
		_backend = nil
	end
	_subscribers = {}
	_state = nil
	_setup_called = false
end

return cpu
