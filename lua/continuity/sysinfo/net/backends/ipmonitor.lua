local awful = require("awful")
local gears = require("gears")
local Process = require("continuity.util.process")

local ipmonitor_mod = {}

---@class IpmonitorOptions
---@field interval integer Polling interval in seconds for byte counter reads, default is 2.

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

---@param line string  Space-separated awk output: "<name> <rx_bytes> <tx_bytes>"
---@return table|nil  { name, rx_bytes, tx_bytes }
function ipmonitor_mod._parse_proc_net_dev_line(line)
	local name, rx, tx = line:match("^(%S+) (%d+) (%d+)$")
	if not name then
		return nil
	end
	return { name = name, rx_bytes = tonumber(rx), tx_bytes = tonumber(tx) }
end

---@param opts? IpmonitorOptions
---@return NetBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 2
	local on_update = nil
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
			else
				devices[info.name] = devices[info.name] or {}
				devices[info.name].state = info.state
				devices[info.name].carrier = info.carrier
			end
			if on_update then
				on_update(build_state())
			end
		end,
	})

	local proc_stats = Process({
		name = "sysinfo.net.ipmonitor.stats",
		cmd = {
			'awk \'NR>2{gsub(/:$/,"",$1); printf "%s %s %s\\n",$1,$2,$10}\' /proc/net/dev',
			'awk \'NR>2{gsub(/:$/,"",$1); printf "sig %s %d\\n",$1,int($4)}\' /proc/net/wireless 2>/dev/null',
		},
		interval = interval,
		stdout = function(line)
			if line:match("^sig ") then
				local name, dbm = line:match("^sig (%S+) (-?%d+)$")
				if name and devices[name] then
					local d = tonumber(dbm)
					devices[name].signal = d ~= 0 and d or nil
				end
				return
			end
			local s = ipmonitor_mod._parse_proc_net_dev_line(line)
			if not s or not devices[s.name] then
				return
			end
			local now = os.time()
			local prev = prev_bytes[s.name]
			local tx_rate, rx_rate = 0, 0
			if prev then
				local dt = now - prev.time
				if dt > 0 then
					tx_rate = math.max(0, (s.tx_bytes - prev.tx) / dt)
					rx_rate = math.max(0, (s.rx_bytes - prev.rx) / dt)
				end
			end
			prev_bytes[s.name] = { tx = s.tx_bytes, rx = s.rx_bytes, time = now }
			devices[s.name].tx_bytes = s.tx_bytes
			devices[s.name].rx_bytes = s.rx_bytes
			devices[s.name].tx_rate = tx_rate
			devices[s.name].rx_rate = rx_rate
			if on_update then
				on_update(build_state())
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
				proc_stats:start()
			end)
		end,
		stop = function(_)
			proc:stop()
			proc_stats:stop()
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
