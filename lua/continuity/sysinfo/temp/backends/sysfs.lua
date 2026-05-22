local Process = require("continuity.util.process")

---@class SysfsOptions
---@field interval?   integer   Polling interval in seconds, defaults to 5.
---@field cpu_device? string    Thermal zone type to expose as cpu; overrides label matching.
---@field exclude?    string[]  Lua patterns matched against zone type; matching devices are omitted.

local MIN_TEMP = -40
local MAX_TEMP = 200

local CPU_LABELS = {
	x86_pkg_temp = true,
	["cpu-thermal"] = true,
	["soc-thermal"] = true,
}

local sysfs = {}

---@param t number|nil  Degrees Celsius
---@return boolean
local function valid_temp(t)
	return t ~= nil and t >= MIN_TEMP and t <= MAX_TEMP
end

---@param zones table<string, table>  Raw zone data keyed by zone path
---@param cpu_device? string
---@return TempDevice|nil
local function select_cpu(zones_list, cpu_device)
	if cpu_device then
		for _, d in ipairs(zones_list) do
			if d.name == cpu_device then
				return d
			end
		end
		return nil
	end
	for _, d in ipairs(zones_list) do
		if CPU_LABELS[d.label] then
			return d
		end
	end
	return nil
end

---@param name string
---@param exclude? string[]
---@return boolean
local function is_excluded(name, exclude)
	if not exclude then
		return false
	end
	for _, pattern in ipairs(exclude) do
		if string.find(name, pattern) then
			return true
		end
	end
	return false
end

---@param lines string[]
---@param cpu_device? string
---@param exclude? string[]
---@return TempState
function sysfs._parse_sysfs_lines(lines, cpu_device, exclude)
	local raw = {}

	for _, line in ipairs(lines) do
		local filepath, value = line:match("^([^:]+):(.*)")
		if filepath and value then
			local dir, filename = filepath:match("^(.+)/([^/]+)$")
			if dir and filename then
				if not raw[dir] then
					raw[dir] = { trip_types = {}, trip_temps = {} }
				end
				local z = raw[dir]
				value = value:match("^%s*(.-)%s*$")

				if filename == "temp" then
					z.temp_raw = tonumber(value)
				elseif filename == "type" then
					z.zone_type = value
				else
					local idx, ftype = filename:match("^trip_point_(%d+)_(.+)$")
					if idx and ftype then
						idx = tonumber(idx)
						if ftype == "type" then
							z.trip_types[idx] = value
						elseif ftype == "temp" then
							z.trip_temps[idx] = tonumber(value)
						end
					end
				end
			end
		end
	end

	local devices = {}

	for _, z in pairs(raw) do
		if z.zone_type and z.temp_raw and not is_excluded(z.zone_type, exclude) then
			local temp = z.temp_raw / 1000
			if valid_temp(temp) then
				local crit, max, first_passive

				local indices = {}
				for idx in pairs(z.trip_types) do
					indices[#indices + 1] = idx
				end
				table.sort(indices)

				for _, idx in ipairs(indices) do
					local tp_type = z.trip_types[idx]
					local tp_raw = z.trip_temps[idx]
					if tp_raw then
						local tp = tp_raw / 1000
						if valid_temp(tp) then
							if tp_type == "critical" and not crit then
								crit = tp
							elseif tp_type == "hot" and not max then
								max = tp
							elseif tp_type == "passive" and not first_passive then
								first_passive = tp
							end
						end
					end
				end

				if not max then
					max = first_passive
				end

				devices[#devices + 1] = {
					name = z.zone_type,
					label = z.zone_type,
					temp = temp,
					crit = crit,
					max = max,
					sensors = {},
				}
			end
		end
	end

	return { devices = devices, cpu = select_cpu(devices, cpu_device) }
end

---@param opts? SysfsOptions
---@return TempBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 5
	local cpu_device = opts.cpu_device
	local exclude = opts.exclude
	local on_update = nil
	local buf = {}

	local proc = Process({
		name = "sysinfo.temp.sysfs",
		cmd = {
			[[awk '{print FILENAME ":" $0}' ]]
				.. [[/sys/class/thermal/thermal_zone*/temp ]]
				.. [[/sys/class/thermal/thermal_zone*/type ]]
				.. [[/sys/class/thermal/thermal_zone*/trip_point_*_type ]]
				.. [[/sys/class/thermal/thermal_zone*/trip_point_*_temp ]]
				.. [[2>/dev/null]],
			"echo '---'",
		},
		interval = interval,
		stdout = function(line)
			if line ~= "---" then
				buf[#buf + 1] = line
				return
			end
			local state = sysfs._parse_sysfs_lines(buf, cpu_device, exclude)
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
