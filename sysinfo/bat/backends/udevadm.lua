local awful = require("awful")
local gears = require("gears")
local Process = require("continuity.util.process")

---@class UdevadmOptions
---@field poll? integer|boolean Whether or not polling should be enabled or a custom rate, Default is 30s

local udevadm_mod = {}

local READ_CMD = [[
  for f in /sys/class/power_supply/*/uevent; do
    [ -f "$f" ] || continue
    dir=$(dirname "$f")
    printf '===:%s\n' "$(basename $dir)"
    cat "$f"
    for attr in charge_control_start_threshold charge_control_end_threshold; do
      tf="$dir/$attr"
      [ -f "$tf" ] && printf 'POWER_SUPPLY_%s=%s\n' \
        "$(echo "$attr" | tr 'a-z' 'A-Z')" "$(cat "$tf")"
    done
  done
]]

---@param stdout string
---@return table  { ac = {name->online_val}, batteries = {name->{field->val}} }
function udevadm_mod._parse_bat_output(stdout)
	local raw = { ac = {}, batteries = {} }
	local cur_name, cur_fields

	local function flush()
		if not cur_name or not cur_fields then
			return
		end
		local t = cur_fields.type or ""
		if t == "Mains" then
			raw.ac[cur_name] = cur_fields.online or "0"
		elseif t == "Battery" then
			raw.batteries[cur_name] = cur_fields
		end
		cur_name, cur_fields = nil, nil
	end

	for line in stdout:gmatch("[^\n]+") do
		local sep = line:match("^===:(.+)$")
		if sep then
			flush()
			cur_name = sep
			cur_fields = {}
		elseif cur_fields then
			local key, val = line:match("^POWER_SUPPLY_(%S-)=(.*)$")
			if key then
				cur_fields[key:lower()] = val
			end
		end
	end
	flush()

	return raw
end

---@param raw table
---@return BatState
function udevadm_mod._compute_bat_state(raw)
	local ac_online = false
	for _, val in pairs(raw.ac) do
		if val == "1" then
			ac_online = true
			break
		end
	end

	local batteries = {}
	local sum_e_now, sum_e_full, sum_e_design, sum_power = 0, 0, 0, 0
	local agg_status = "Unknown"
	local charge_controlled = false

	for name, fields in pairs(raw.batteries) do
		local voltage = tonumber(fields.voltage_now) or 0

		local function to_wh(energy_field, charge_field)
			local e = tonumber(fields[energy_field])
			if e then
				return e / 1e6
			end
			local c = tonumber(fields[charge_field])
			if c and voltage > 0 then
				return (c * voltage) / 1e12
			end
			return 0
		end

		local e_now = to_wh("energy_now", "charge_now")
		local e_full = to_wh("energy_full", "charge_full")
		local e_design = to_wh("energy_full_design", "charge_full_design")
		local power_raw = tonumber(fields.power_now)
		local power = power_raw and (power_raw / 1e6)
			or (tonumber(fields.current_now) and voltage > 0 and (tonumber(fields.current_now) * voltage) / 1e12 or 0)

		local perc = tonumber(fields.capacity) or (e_full > 0 and math.floor((e_now / e_full) * 100) or 0)
		local status = fields.status or "Unknown"
		local start_thresh = tonumber(fields.charge_control_start_threshold)
		local end_thresh = tonumber(fields.charge_control_end_threshold)
		if start_thresh and end_thresh and perc >= start_thresh and perc <= end_thresh then
			charge_controlled = true
		end

		batteries[#batteries + 1] = {
			name = name,
			status = status,
			perc = perc,
			energy_now = e_now,
			energy_full = e_full,
			charge_control_start_threshold = start_thresh,
			charge_control_end_threshold = end_thresh,
		}

		sum_e_now = sum_e_now + e_now
		sum_e_full = sum_e_full + e_full
		sum_e_design = sum_e_design + e_design
		sum_power = sum_power + power

		if status == "Discharging" then
			agg_status = "Discharging"
		elseif status == "Charging" and agg_status ~= "Discharging" then
			agg_status = "Charging"
		elseif status == "Not charging" and (agg_status == "Unknown" or agg_status == "NotCharging") then
			agg_status = "NotCharging"
		end
	end

	local perc = sum_e_full > 0 and math.floor((sum_e_now / sum_e_full) * 100) or 0
	local capacity = sum_e_design > 0 and math.floor((sum_e_full / sum_e_design) * 100) or 0

	return {
		status = agg_status,
		ac_online = ac_online,
		perc = perc,
		energy_now = sum_e_now,
		energy_full = sum_e_full,
		energy_design = sum_e_design,
		power_now = sum_power,
		capacity = capacity,
		charge_controlled = charge_controlled,
		batteries = batteries,
	}
end

---@param opts UdevadmOptions
---@return BatteryBackend
local function create(opts)
	opts = opts or {}
	local poll_opt = opts.poll
	if poll_opt == nil then
		poll_opt = true
	end
	local poll_interval = (poll_opt == true) and 30 or (type(poll_opt) == "number" and poll_opt > 0 and poll_opt or nil)

	local on_update = nil
	local poll_timer = nil

	local function do_read()
		awful.spawn.easy_async({ "sh", "-c", READ_CMD }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or stdout == "" then
				gears.debug.print_warning("sysinfo.bat.udevadm: sysfs read failed")
				return
			end
			local raw = udevadm_mod._parse_bat_output(stdout)
			if next(raw.batteries) == nil then
				gears.debug.print_warning("sysinfo.bat.udevadm: no battery devices found")
				return
			end
			if on_update then
				on_update(udevadm_mod._compute_bat_state(raw))
			end
		end)
	end

	local proc = Process({
		name = "sysinfo.bat.udevadm",
		cmd = { "udevadm", "monitor", "--udev", "--subsystem-match=power_supply" },
		stdout = function(line)
			if line:match("^UDEV%s+%[") then
				do_read()
			end
		end,
	})

	return {
		start = function(_, cb)
			on_update = cb
			do_read()
			proc:start()
			if poll_interval then
				poll_timer = gears.timer({ timeout = poll_interval, autostart = true, callback = do_read })
			end
		end,
		stop = function(_)
			proc:stop()
			if poll_timer then
				poll_timer:stop()
				poll_timer = nil
			end
			on_update = nil
		end,
	}
end

return setmetatable(udevadm_mod, {
	__call = function(_, opts)
		return create(opts)
	end,
})
