---@class continuity.sysinfo
---@field bat  BatteryMonitor
---@field cpu  CpuMonitor
---@field mem  MemMonitor
---@field net  NetMonitor
---@field temp TempMonitor
local M = setmetatable({}, {
	__index = function(self, k)
		local mod = require("continuity.sysinfo." .. k)
		rawset(self, k, mod)
		return mod
	end,
})

return M
