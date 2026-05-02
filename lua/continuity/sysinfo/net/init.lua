local gears = require("gears")
local ipmonitor = require("continuity.sysinfo.net.backends.ipmonitor")

---@alias DeviceState "up"|"down"
local DeviceState = {
	Up = "up",
	Down = "down",
}

---@class NetDeviceState
---@field state    DeviceState "up" or "down"
---@field carrier  boolean     Physical link present
---@field tx_rate  number      Bytes per second since last sample
---@field rx_rate  number      Bytes per second since last sample
---@field tx_bytes integer     Cumulative bytes transmitted from sysfs
---@field rx_bytes integer     Cumulative bytes received from sysfs
---@field wifi     boolean     True if the interface is a wireless device
---@field signal   number|nil  Signal strength in dBm; nil if not wifi or no carrier

---@class NetState
---@field devices  table<string, NetDeviceState>  Keyed by interface name
---@field tx_rate  number                         Bytes per second total across all devices
---@field rx_rate  number                         Bytes per second total across all devices

---@class NetBackend
---@field start fun(self, cb: fun(state: NetState))
---@field stop  fun(self)

---@class NetOptions
---@field backend? NetBackend  The backend to provide network monitoring, defaults to ipmonitor backend.

local _state = nil ---@type NetState|nil
local _subscribers = {}
local _backend = nil
local _setup_called = false

local function _on_update(data)
	_state = data
	for _, sub in ipairs(_subscribers) do
		sub(_state)
	end
end

local net = {}

net.DeviceState = DeviceState

--- Initiate network monitoring.
---@param opts? NetOptions
function net.setup(opts)
	if _setup_called then
		gears.debug.print_warning("sysinfo.net: setup() called more than once; ignoring")
		return
	end
	_setup_called = true
	opts = opts or {}
	_backend = opts.backend or ipmonitor()
	_backend:start(_on_update)
end

--- Subscribe to receive network state updates as available.
---@param fn fun(state: NetState)  Callback to receive updates.
---@return fun()                   Unsubscribe function.
function net:subscribe(fn)
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

--- Get the network state if available.
---@return NetState|nil
function net.state()
	return _state
end

--- Stop network monitoring.
function net.stop()
	if _backend then
		_backend:stop()
		_backend = nil
	end
	_subscribers = {}
	_state = nil
	_setup_called = false
end

return net
