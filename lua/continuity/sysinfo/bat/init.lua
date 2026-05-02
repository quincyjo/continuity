local gears = require("gears")
local udevadm = require("continuity.sysinfo.bat.backends.udevadm")

---@alias BatteryStatus "Discharging"|"Charging"|"NotCharging"

local BatteryStatus = {
	Discharging = "Discharging",
	Charging = "Charging",
	NotCharging = "NotCharging",
}

---@class BatteryState
---@field name         string         e.g. "BAT0"
---@field status       BatteryStatus  "Discharging" or "Charging".
---@field perc         number         Percentage (0-100)
---@field energy_now   number         Watt-hours, current charge
---@field energy_full  number         Watt-hours, current full capacity
---@field charge_control_start_threshold  number|nil  Start threshold %; nil if unsupported
---@field charge_control_end_threshold    number|nil  End threshold %; nil if unsupported

---@class BatState
---@field status          BatteryStatus  Aggregate: "Discharging" if any battery discharging; else "Charging", "Full",
---                                      or "Unknown"
---@field ac_online       boolean        True if any AC adapter is online
---@field perc            number         Aggregate percentage (0-100)
---@field energy_now      number         Watt-hours, sum across batteries
---@field energy_full     number         Watt-hours, sum of current full capacities
---@field energy_design   number         Watt-hours, sum of design capacities
---@field power_now       number         Watts, instantaneous draw (discharging) or charge rate
---@field power_average   number         Watts, EMA-smoothed draw or charge rate
---@field capacity        number         Health percentage (energy_full / energy_design * 100)
---@field charge_controlled boolean       True if any battery's perc is within its charge control window
---@field batteries       BatteryState[] Per-battery breakdown

---@class BatteryBackend
---@field start fun(self, cb: fun(state: BatState))
---@field stop  fun(self)

---@class BatteryOptions
---@field backend?     BatteryBackend  The backend to provide battery monitoring, defaults to udevadm backend.
---@field power_alpha? number          EMA Alpha, 0-1, default is 0.1 (10 samples)

local _subscribers = {} ---@type fun(state: BatState)[]
local _backend = nil ---@type BatteryBackend|nil
local _setup_called = false
local _power_average = nil ---@type number|nil
local _power_alpha = 0.1 -- EMA weight for the newest sample

local bat = {}

---@type BatState|nil
bat.state = nil

local function _on_update(data)
	-- Reset EMA when power flow direction changes
	if bat.state and bat.state.status ~= data.status then
		_power_average = nil
	end
	if _power_average == nil then
		_power_average = data.power_now
	else
		_power_average = _power_alpha * data.power_now + (1 - _power_alpha) * _power_average
	end
	data.power_average = _power_average

	bat.state = data
	for _, sub in ipairs(_subscribers) do
		sub(bat.state)
	end
end

--- Initiates battery monitoring.
---@param opts? BatteryOptions
function bat.setup(opts)
	if _setup_called then
		gears.debug.print_warning("sysinfo.bat: setup() called more than once; ignoring")
		return
	end
	_setup_called = true
	opts = opts or {}
	if opts.power_alpha ~= nil then
		_power_alpha = opts.power_alpha
	end
	_backend = opts.backend or udevadm()
	_backend:start(_on_update)
end

--- Subscribe to changes to the battery state.
---@param fn fun(state: BatState)  Callback to receive updates.
---@return fun()                   Unsubscribe function.
function bat:subscribe(fn)
	_subscribers[#_subscribers + 1] = fn
	if bat.state ~= nil then
		fn(bat.state)
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

--- Calculate the time remaining based of the rolling average power.
--- If the state is not Discharging or there is power, nil is returned.
---@return number|nil
function bat.time_remaining()
	if not bat.state or bat.state.status ~= BatteryStatus.Discharging or bat.state.power_now == 0 then
		return
	end
	return (bat.state.energy_now / bat.state.power_average) * 3600
end

--- Calculate the until fully charged based of the rolling average power.
--- If the state is not Charging or there is power, nil is returned.
---@return number|nil
function bat.time_until_full()
	if not bat.state or bat.state.status ~= BatteryStatus.Charging or bat.state.power_now == 0 then
		return
	end
	return ((bat.state.energy_full - bat.state.energy_now) / bat.state.power_average) * 3600
end

--- Stop the battery monitoring.
function bat.stop()
	if _backend then
		_backend:stop()
		_backend = nil
	end
	_subscribers = {}
	bat.state = nil
	_setup_called = false
	_power_average = nil
	_power_alpha = 0.3
end

bat.BatteryStatus = BatteryStatus

return bat
