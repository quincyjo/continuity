local Monitor = require("continuity.monitor")

---@class TempSensor
---@field label  string   Sensor label (temp*_label from hwmon, or zone type from thermal)
---@field temp   number   Degrees Celsius
---@field crit?  number   Shutdown threshold in °C, nil if unavailable or bogus
---@field max?   number   High-water mark in °C, nil if unavailable or bogus

---@class TempDevice : TempSensor
---@field name    string       hwmon device name or thermal zone type
---@field sensors TempSensor[] Sub-sensors (hwmon temp2..N); empty for thermal backend

---@class TempState
---@field devices TempDevice[] All devices reported by the backend
---@field cpu?    TempDevice   CPU device, selected by known label or cpu_device option

---@class TempBackend : MonitorBackend<TempState>

---@class TempOptions : MonitorOptions<TempState>
---@field backend?    TempBackend  Backend to use; defaults to hwmon thermal backend.
---@field cpu_device? string       hwmon name or thermal zone type to use as cpu device.
---@field exclude?    string[]     Lua patterns matched against device name; matching devices are omitted.

---@class TempMonitor : Monitor<TempState, TempOptions>
local temp = Monitor({
	name = "temp",
	configure = function(_, opts)
		opts = opts or {}
		return opts.backend or require("continuity.sysinfo.temp.backends.hwmon")(opts)
	end,
})

return temp
