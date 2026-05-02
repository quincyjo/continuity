local awful = require("awful")
local gears = require("gears")
local Process = require("continuity.util.process")

local ipmonitor_mod = {}

---@class IpmonitorOptions
---@field interval integer Polling interval, default is 2.

---@param line string
---@return table|nil  { name, state, carrier, deleted }
function ipmonitor_mod._parse_ip_link_line(line)
	local deleted = line:match("^Deleted ") ~= nil
	local clean = deleted and line:sub(9) or line

	local raw_name = clean:match("^%d+: (%S+):")
	if not raw_name then
		return nil
	end

	local name = raw_name:match("^([^@]+)") or raw_name
	local flags_section = clean:match("<([^>]*)>") or ""
	if flags_section:find("LOOPBACK", 1, true) then
		return nil
	end

	if deleted then
		return { name = name, deleted = true, state = "down", carrier = false }
	end

	local state_str = clean:match("state (%S+)") or "UNKNOWN"
	local up = state_str == "UP" or state_str == "UNKNOWN"
	local carrier = flags_section:find("LOWER_UP", 1, true) ~= nil

	return { name = name, deleted = false, state = up and "up" or "down", carrier = carrier }
end

---@param stdout string
---@return table<string, table>
function ipmonitor_mod._parse_stats_output(stdout)
	local devs = {}
	for line in stdout:gmatch("[^\n]+") do
		local name, key, val = line:match("^dev:([^:]+):([^:]+):(.+)$")
		if name and key then
			devs[name] = devs[name] or {}
			if key == "tx" then
				devs[name].tx_bytes = tonumber(val) or 0
			elseif key == "rx" then
				devs[name].rx_bytes = tonumber(val) or 0
			elseif key == "state" then
				devs[name].state = val
			elseif key == "carrier" then
				devs[name].carrier = val == "1"
			elseif key == "wifi" then
				devs[name].wifi = val == "1"
			elseif key == "signal" then
				local s = tonumber(val)
				devs[name].signal = s ~= 0 and s or nil
			end
		end
	end
	return devs
end

local function build_stats_cmd(dev_names)
	local parts = {}
	for _, dev in ipairs(dev_names) do
		parts[#parts + 1] = string.format(
			"printf 'dev:%s:tx:%%s\\ndev:%s:rx:%%s\\ndev:%s:state:%%s\\ndev:%s:carrier:%%s\\ndev:%s:wifi:%%s\\n' "
				.. '"$(cat /sys/class/net/%s/statistics/tx_bytes 2>/dev/null || echo 0)" '
				.. '"$(cat /sys/class/net/%s/statistics/rx_bytes 2>/dev/null || echo 0)" '
				.. '"$(cat /sys/class/net/%s/operstate 2>/dev/null || echo unknown)" '
				.. '"$(cat /sys/class/net/%s/carrier 2>/dev/null || echo 0)" '
				.. '"$(grep -c DEVTYPE=wlan /sys/class/net/%s/uevent 2>/dev/null || echo 0)"',
			dev,
			dev,
			dev,
			dev,
			dev,
			dev,
			dev,
			dev,
			dev,
			dev
		)
	end
	-- Append wifi signal levels from /proc/net/wireless (covers all wifi ifaces at once).
	-- Format: "  wlan0: 0000  54.  -56.  -256. ..." — field 4 is signal level in dBm.
	parts[#parts + 1] = 'awk \'NR>2{gsub(/:$/,"",$1);printf "dev:%s:signal:%d\\n",$1,int($4)}\''
		.. " /proc/net/wireless 2>/dev/null"
	return table.concat(parts, "\n")
end

---@param opts? IpmonitorOptions
---@return NetBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 2
	local on_update = nil
	local timer = nil
	local devices = {}
	local prev_bytes = {}

	local function build_state()
		local total_tx, total_rx = 0, 0
		local devs = {}
		for name, d in pairs(devices) do
			total_tx = total_tx + (d.tx_rate or 0)
			total_rx = total_rx + (d.rx_rate or 0)
			devs[name] = d
		end
		return { devices = devs, tx_rate = total_tx, rx_rate = total_rx }
	end

	local function read_stats()
		local dev_names = {}
		for name in pairs(devices) do
			dev_names[#dev_names + 1] = name
		end
		if #dev_names == 0 then
			return
		end

		awful.spawn.easy_async({ "sh", "-c", build_stats_cmd(dev_names) }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 then
				return
			end
			local now = os.time()
			local stats = ipmonitor_mod._parse_stats_output(stdout)

			for name, s in pairs(stats) do
				local prev = prev_bytes[name]
				local tx_rate, rx_rate = 0, 0
				if prev then
					local dt = now - prev.time
					if dt > 0 then
						tx_rate = math.max(0, (s.tx_bytes - prev.tx) / dt)
						rx_rate = math.max(0, (s.rx_bytes - prev.rx) / dt)
					end
				end
				prev_bytes[name] = { tx = s.tx_bytes, rx = s.rx_bytes, time = now }

				local existing = devices[name] or {}
				devices[name] = {
					state = s.state or existing.state or "down",
					carrier = s.carrier ~= nil and s.carrier or (existing.carrier or false),
					tx_rate = tx_rate,
					rx_rate = rx_rate,
					tx_bytes = s.tx_bytes or 0,
					rx_bytes = s.rx_bytes or 0,
					wifi = s.wifi ~= nil and s.wifi or (existing.wifi or false),
					signal = s.signal,
				}
			end

			if on_update then
				on_update(build_state())
			end
		end)
	end

	local proc = Process({
		name = "sysinfo.net.ipmonitor",
		cmd = { "sh", "-c", "ip monitor link | grep --line-buffered -E '^[0-9]|^Deleted'" },
		stdout = function(line)
			local info = ipmonitor_mod._parse_ip_link_line(line)
			if not info then
				return
			end
			if info.deleted then
				devices[info.name] = nil
				prev_bytes[info.name] = nil
				if on_update then
					on_update(build_state())
				end
			else
				devices[info.name] = devices[info.name] or {}
				devices[info.name].state = info.state
				devices[info.name].carrier = info.carrier
				read_stats()
			end
		end,
	})

	return {
		start = function(_, cb)
			on_update = cb
			local DISCOVER_CMD = "ip link\n"
				.. 'awk \'NR>2{gsub(/:$/,"",$1);printf "wifi:%s\\n",$1}\''
				.. " /proc/net/wireless 2>/dev/null"
			awful.spawn.easy_async({ "sh", "-c", DISCOVER_CMD }, function(stdout, _, _, exitcode)
				if exitcode ~= 0 then
					gears.debug.print_warning("sysinfo.net.ipmonitor: 'ip link' failed, not starting")
					return
				end
				-- First pass: build device table from ip link lines (wifi=false initially)
				for line in stdout:gmatch("[^\n]+") do
					local info = ipmonitor_mod._parse_ip_link_line(line)
					if info and not info.deleted then
						devices[info.name] = {
							state = info.state,
							carrier = info.carrier,
							tx_rate = 0,
							rx_rate = 0,
							tx_bytes = 0,
							rx_bytes = 0,
							wifi = false,
							signal = nil,
						}
					end
				end
				-- Second pass: mark wifi interfaces from /proc/net/wireless lines
				for line in stdout:gmatch("[^\n]+") do
					local name = line:match("^wifi:(.+)$")
					if name and devices[name] then
						devices[name].wifi = true
					end
				end
				if on_update then
					on_update(build_state())
				end
				proc:start()
				timer = gears.timer({ timeout = interval, autostart = true, callback = read_stats })
			end)
		end,
		stop = function(_)
			proc:stop()
			if timer then
				timer:stop()
			end
			timer = nil
			on_update = nil
			devices = {}
			prev_bytes = {}
		end,
	}
end

return setmetatable(ipmonitor_mod, {
	__call = function(_, opts)
		return create(opts)
	end,
})
