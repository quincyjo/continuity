---@class continuity
---@field sysinfo      continuity.sysinfo
---@field tools        continuity.tools
---@field util         continuity.util
---@field alttab       continuity.alttab
---@field audio        continuity.audio
---@field backlight    continuity.backlight
---@field compat       continuity.compat
---@field media        continuity.media
---@field observable   ObservableClass
---@field history      HistoryClass
local M = setmetatable({}, {
	__index = function(self, k)
		local mod = require("continuity." .. k)
		rawset(self, k, mod)
		return mod
	end,
})

return M
