local Process = require("continuity.util.process")

---@class SysfsOptions
---@field interval? integer Polling interval, defaults to 5.

local sysfs = {}

---@param lines string[]
---@return TempState
function sysfs._parse_temp_lines(lines)
	local zones = {}
	for _, line in ipairs(lines) do
		local zone, val = line:match("^(.+)/temp:(%d+)$")
		if zone then
			zones[zone] = tonumber(val) / 1000
		end
	end
	local sum, count = 0, 0
	for _, v in pairs(zones) do
		sum = sum + v
		count = count + 1
	end
	return { zones = zones, avg = count > 0 and (sum / count) or 0 }
end

---@param opts? SysfsOptions
---@return TempBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 5
	local on_update = nil
	local buf = {}

	local proc = Process({
		name = "sysinfo.temp.sysfs",
		cmd = {
			[[awk '{print FILENAME ":" $1}' /sys/devices/virtual/thermal/thermal_zone*/temp 2>/dev/null]],
			"echo '---'",
		},
		interval = interval,
		stdout = function(line)
			if line ~= "---" then
				buf[#buf + 1] = line
				return
			end
			local state = sysfs._parse_temp_lines(buf)
			buf = {}
			if on_update then
				on_update(state)
			end
		end,
		exit = function()
			buf = {}
		end,
	})

	return {
		start = function(_, cb)
			on_update = cb
			proc:start()
		end,
		stop = function(_)
			proc:stop()
			on_update = nil
		end,
	}
end

return setmetatable(sysfs, {
	__call = function(_, opts)
		return create(opts)
	end,
})
