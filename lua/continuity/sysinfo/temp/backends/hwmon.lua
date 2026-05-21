local Process = require("continuity.util.process")

---@class HwmonOptions
---@field interval?   integer   Polling interval in seconds, defaults to 5.
---@field cpu_device? string    hwmon device name to expose as cpu; overrides label matching.
---@field exclude?    string[]  Lua patterns matched against hwmon device name; matching devices are omitted.

local MIN_TEMP = -40
local MAX_TEMP = 200

local CPU_LABELS = { "Package id 0", "Tdie", "Tctl" }

local hwmon = {}

---@param t number|nil  Degrees Celsius
---@return boolean
local function valid_temp(t)
	return t ~= nil and t >= MIN_TEMP and t <= MAX_TEMP
end

---@param val number|nil  Raw millidegree value
---@return number|nil  Filtered Celsius value, or nil if bogus
local function threshold(val)
	if not val then
		return nil
	end
	local t = val / 1000
	return valid_temp(t) and t or nil
end

---@param devices_list TempDevice[]
---@param cpu_device? string
---@return TempDevice|nil
local function select_cpu(devices_list, cpu_device)
	if cpu_device then
		for _, d in ipairs(devices_list) do
			if d.name == cpu_device then
				return d
			end
		end
		return nil
	end
	local label_set = {}
	for _, l in ipairs(CPU_LABELS) do
		label_set[l] = true
	end
	for _, d in ipairs(devices_list) do
		if d.label and label_set[d.label] then
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
function hwmon._parse_hwmon_lines(lines, cpu_device, exclude)
	local raw = {}

	for _, line in ipairs(lines) do
		local filepath, value = line:match("^([^:]+):(.*)")
		if filepath and value then
			local dir, filename = filepath:match("^(.+)/([^/]+)$")
			if dir and filename then
				if not raw[dir] then
					raw[dir] = { sensors = {} }
				end
				local d = raw[dir]
				value = value:match("^%s*(.-)%s*$")

				if filename == "name" then
					d.dev_name = value
				else
					local idx, ftype = filename:match("^temp(%d+)_(.+)$")
					if idx and ftype then
						idx = tonumber(idx)
						if not d.sensors[idx] then
							d.sensors[idx] = {}
						end
						local s = d.sensors[idx]
						if ftype == "input" then
							s.input = tonumber(value)
						elseif ftype == "label" then
							s.label = value
						elseif ftype == "crit" then
							s.crit = tonumber(value)
						elseif ftype == "max" then
							s.max = tonumber(value)
						end
					end
				end
			end
		end
	end

	local devices = {}

	for _, d in pairs(raw) do
		local s1 = d.sensors[1]
		if s1 and s1.input and not is_excluded(d.dev_name or "", exclude) then
			local temp1 = s1.input / 1000
			if valid_temp(temp1) then
				-- Build sensors for temp2..N in index order
				local indices = {}
				for idx in pairs(d.sensors) do
					if idx > 1 then
						indices[#indices + 1] = idx
					end
				end
				table.sort(indices)

				local sensor_list = {}
				for _, idx in ipairs(indices) do
					local s = d.sensors[idx]
					if s.input then
						local t = s.input / 1000
						if valid_temp(t) then
							sensor_list[#sensor_list + 1] = {
								label = s.label,
								temp = t,
								crit = threshold(s.crit),
								max = threshold(s.max),
							}
						end
					end
				end

				devices[#devices + 1] = {
					name = d.dev_name,
					label = s1.label,
					temp = temp1,
					crit = threshold(s1.crit),
					max = threshold(s1.max),
					sensors = sensor_list,
				}
			end
		end
	end

	return { devices = devices, cpu = select_cpu(devices, cpu_device) }
end

---@param opts? HwmonOptions
---@return TempBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 5
	local cpu_device = opts.cpu_device
	local exclude = opts.exclude
	local on_update = nil
	local buf = {}

	local proc = Process({
		name = "sysinfo.temp.hwmon",
		cmd = {
			[[awk '{print FILENAME ":" $0}' ]]
				.. [[/sys/class/hwmon/hwmon*/name ]]
				.. [[/sys/class/hwmon/hwmon*/temp*_input ]]
				.. [[/sys/class/hwmon/hwmon*/temp*_label ]]
				.. [[/sys/class/hwmon/hwmon*/temp*_crit ]]
				.. [[/sys/class/hwmon/hwmon*/temp*_max ]]
				.. [[2>/dev/null]],
			"echo '---'",
		},
		interval = interval,
		stdout = function(line)
			if line ~= "---" then
				buf[#buf + 1] = line
				return
			end
			local state = hwmon._parse_hwmon_lines(buf, cpu_device, exclude)
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

return setmetatable(hwmon, {
	__call = function(_, opts)
		return create(opts)
	end,
})
