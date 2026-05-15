local Monitor = require("continuity.monitor")

---@class TempState
---@field zones  table<string, number>  Degrees Celsius keyed by sysfs path (e.g. "/sys/.../thermal_zone0/temp")
---@field avg    number                 Arithmetic mean across all zones in degrees Celsius

---@class TempBackend : MonitorBackend<TempState>

---@class TempOptions : MonitorOptions<TempState>
---@field backend? TempBackend  The backend to provide temperature monitoring, defaults to sysfs backend.

---@class TempMonitor : Monitor<TempState, TempOptions>
---@field setup fun(opts: TempOptions?)

---@type TempMonitor
local temp = Monitor({
	name = "temp",
	configure = function(_, opts)
		opts = opts or {}
		return opts.backend or require("continuity.sysinfo.temp.backends.sysfs")()
	end,
})

---@type TempMonitor
return temp
