local Monitor = require("continuity.monitor")

---@alias BatteryStatus "Discharging"|"Charging"|"NotCharging"|"Unknown"

local BatteryStatus = {
	Discharging = "Discharging",
	Charging = "Charging",
	NotCharging = "NotCharging",
	Unknown = "Unknown",
}

---@class BatteryMonitor : Monitor<BatState, BatteryOptions>
---@field setup           fun(opts: BatteryOptions?)
---@field time_remaining  fun(): number|nil     Time remaining in seconds; nil if not discharging
---@field time_until_full fun(): number|nil     Time until fully charged in seconds; nil if not charging
---@field BatteryStatus   table<string, BatteryStatus>

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
---@field time_remaining  number|nil     Time remaining in seconds; nil if not discharging
---@field time_until_full number|nil     Time until fully charged in seconds; nil if not charging
---@field batteries       BatteryState[] Per-battery breakdown

---@class BatteryBackend : MonitorBackend<BatState>

---@class BatteryOptions : MonitorOptions<BatState>
---@field backend?     BatteryBackend  The backend to provide battery monitoring, defaults to udevadm backend.
---@field power_alpha? number          EMA Alpha, 0-1, default is 0.1 (10 samples)

local _power_average = nil ---@type number|nil
local _power_alpha = 0.1 -- EMA weight for the newest sample

--- Calculate the time remaining based of the rolling average power.
--- If the state is not Discharging or there is power, nil is returned.
---@param state BatState
---@return number|nil
local function calculate_time_remaining(state)
	if not state or state.status ~= BatteryStatus.Discharging or state.power_now == 0 then
		return
	end
	return (state.energy_now / state.power_average) * 3600
end

--- Calculate the until fully charged based of the rolling average power.
--- If the state is not Charging or there is power, nil is returned.
---@param state BatState
---@return number|nil
local function calculate_time_until_full(state)
	if not state or state.status ~= BatteryStatus.Charging or state.power_now == 0 then
		return
	end
	return ((state.energy_full - state.energy_now) / state.power_average) * 3600
end

---@type BatteryMonitor
local bat = Monitor({
	name = "bat",
	configure = function(_, opts)
		opts = opts or {}
		_power_alpha = opts.power_alpha or 0.1
		return opts.backend or require("continuity.sysinfo.bat.backends.udevadm")()
	end,
	on_update = function(self, data)
		-- Reset EMA when power flow direction changes
		if self.state and self.state.status ~= data.status then
			_power_average = nil
		end
		if _power_average == nil then
			_power_average = data.power_now
		else
			_power_average = _power_alpha * data.power_now + (1 - _power_alpha) * _power_average
		end
		data.power_average = _power_average
		data.time_remaining = calculate_time_remaining(data)
		data.time_until_full = calculate_time_until_full(data)
		return data
	end,
	cleanup = function(_)
		_power_average = nil
		_power_alpha = 0.1
	end,
})

--- Calculate the time remaining based of the rolling average power.
--- If the state is not Discharging or there is power, nil is returned.
---@return number|nil
---@deprecated Read time_remaining from the state instead.
function bat.time_remaining()
	return bat.state and bat.state.time_remaining
end

--- Calculate the until fully charged based of the rolling average power.
--- If the state is not Charging or there is power, nil is returned.
---@return number|nil
---@deprecated Read time_until_full from the state instead.
function bat.time_until_full()
	return bat.state and bat.state.time_until_full
end

bat.BatteryStatus = BatteryStatus

return bat
