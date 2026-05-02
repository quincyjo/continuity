local awful = require("awful")
local gears = require("gears")
local Process = require("continuity.util.process")

---@class SysfsBacklightOptions
---@field interval? integer

local sysfs = {}

---@param name string
---@return BacklightKind
function sysfs._kind_from_name(name)
	if name:match("kbd") or name:match("keyboard") then
		return "keyboard"
	end
	return "display"
end

---@param raw integer
---@param max integer
---@return integer
function sysfs._raw_to_perc(raw, max)
	if raw >= max then
		return 100
	end
	if raw <= 0 then
		return 0
	end
	return math.floor(raw / (max + 1) * 100 + 0.5)
end

---@param perc number
---@param max integer
---@return integer
function sysfs._perc_to_raw(perc, max)
	if perc >= 100 then
		return max
	end
	return math.min(max, math.floor(perc / 100 * (max + 1) + 0.5))
end

---@param line string
---@return string|nil, integer|nil
function sysfs._parse_line(line)
	local id, raw = line:match("^([^:]+):(%d+)$")
	if id and raw then
		return id, tonumber(raw)
	end
	return nil, nil
end

---@param opts? SysfsBacklightOptions
---@return BacklightBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 5
	local callbacks = nil
	local known = {}
	local buf = {}

	local proc = Process({
		name = "backlight.sysfs",
		cmd = {
			[[for f in /sys/class/backlight/*/brightness; do
  [ -f "$f" ] || continue
  id=$(basename $(dirname "$f"))
  printf '%s:%s\n' "$id" "$(cat "$f")"
done]],
			"echo '---'",
		},
		interval = interval,
		stdout = function(line)
			if line ~= "---" then
				buf[#buf + 1] = line
				return
			end

			local seen = {}
			for _, raw_line in ipairs(buf) do
				local id, raw = sysfs._parse_line(raw_line)
				if id then
					seen[id] = raw
				end
			end
			buf = {}

			for id, raw in pairs(seen) do
				if not known[id] then
					known[id] = { pending = true }
					local max_path = string.format("/sys/class/backlight/%s/max_brightness", id)
					local write_path = string.format("/sys/class/backlight/%s/brightness", id)
					awful.spawn.easy_async({ "sh", "-c", string.format("cat '%s'", max_path) }, function(stdout_max)
						if not known[id] then
							return
						end
						local max = tonumber(stdout_max)
						if not max then
							known[id] = nil
							return
						end
						awful.spawn.easy_async(
							{ "sh", "-c", string.format("test -w '%s'", write_path) },
							function(_, _, _, exit)
								if not known[id] then
									return
								end
								if exit ~= 0 then
									gears.debug.print_warning(
										string.format(
											"backlight.sysfs: %s is not writable (add user to video group)",
											id
										)
									)
								end
								local brightness = sysfs._raw_to_perc(raw, max)
								known[id] = { max_brightness = max, brightness = brightness, raw = raw }
								if callbacks then
									callbacks.on_device_added({
										id = id,
										kind = sysfs._kind_from_name(id),
										brightness = brightness,
										raw = raw,
										steps = max + 1,
									})
								end
							end
						)
					end)
				elseif not known[id].pending then
					local brightness = sysfs._raw_to_perc(raw, known[id].max_brightness)
					if brightness ~= known[id].brightness then
						known[id].brightness = brightness
						known[id].raw = raw
						if callbacks then
							callbacks.on_change(id, brightness)
						end
					end
				end
			end

			local removed = {}
			for id in pairs(known) do
				if not seen[id] then
					removed[#removed + 1] = id
				end
			end
			for _, id in ipairs(removed) do
				local was_pending = known[id] and known[id].pending
				known[id] = nil
				if callbacks and not was_pending then
					callbacks.on_device_removed(id)
				end
			end
		end,
		exit = function()
			buf = {}
		end,
	})

	---@type table<string, boolean>
	local adj_in_progress = {}
	---@type table<string, integer>
	local adj_queued = {}
	---@type table<string, function>
	local adj_cb_queued = {}

	---@type table<string, boolean>
	local adj_step_in_progress = {}
	---@type table<string, integer>
	local adj_step_queued = {}
	---@type table<string, function>
	local adj_step_cb_queued = {}

	return {
		start = function(_, cbs)
			callbacks = cbs
			proc:start()
		end,
		stop = function(_)
			proc:stop()
			callbacks = nil
		end,
		set_perc = function(_, id, perc, cb)
			local entry = known[id]
			if not entry or entry.pending then
				return
			end
			perc = math.max(0, math.min(100, perc))
			local raw = sysfs._perc_to_raw(perc, entry.max_brightness)
			local real_perc = sysfs._raw_to_perc(raw, entry.max_brightness)
			awful.spawn.easy_async(
				{ "sh", "-c", string.format("echo %d > '/sys/class/backlight/%s/brightness'", raw, id) },
				function(_, _, _, exitcode)
					if exitcode == 0 then
						entry.raw = raw
						entry.brightness = real_perc
						cb(real_perc, raw)
					end
				end
			)
		end,
		adjust_perc = function(self, id, delta, cb)
			if delta == 0 then
				return
			end
			local entry = known[id]
			if not entry or entry.pending then
				return
			end
			if adj_in_progress[id] then
				adj_queued[id] = delta
				adj_cb_queued[id] = cb
				return
			end
			adj_in_progress[id] = true
			local new_perc = math.max(0, math.min(100, entry.brightness + delta))
			local raw = sysfs._perc_to_raw(new_perc, entry.max_brightness)
			local real_perc = sysfs._raw_to_perc(raw, entry.max_brightness)
			awful.spawn.easy_async(
				{ "sh", "-c", string.format("echo %d > '/sys/class/backlight/%s/brightness'", raw, id) },
				function(_, _, _, exitcode)
					local next_delta = adj_queued[id]
					local next_cb = adj_cb_queued[id]
					adj_queued[id] = nil
					adj_cb_queued[id] = nil
					adj_in_progress[id] = nil
					if exitcode == 0 then
						entry.raw = raw
						entry.brightness = real_perc
						cb(real_perc, raw)
					end
					if next_delta then
						self:adjust_perc(id, next_delta, next_cb)
					end
				end
			)
		end,
		set = function(_, id, step, cb)
			local entry = known[id]
			if not entry or entry.pending then
				return
			end
			local raw = math.max(0, math.min(entry.max_brightness, step))
			awful.spawn.easy_async(
				{ "sh", "-c", string.format("echo %d > '/sys/class/backlight/%s/brightness'", raw, id) },
				function(_, _, _, exitcode)
					if exitcode == 0 then
						entry.raw = raw
						entry.brightness = sysfs._raw_to_perc(raw, entry.max_brightness)
						cb(entry.brightness, raw)
					end
				end
			)
		end,
		adjust = function(self, id, delta, cb)
			if delta == 0 then
				return
			end
			local entry = known[id]
			if not entry or entry.pending then
				return
			end
			if adj_step_in_progress[id] then
				adj_step_queued[id] = delta
				adj_step_cb_queued[id] = cb
				return
			end
			adj_step_in_progress[id] = true
			local new_raw = math.max(0, math.min(entry.max_brightness, entry.raw + delta))
			awful.spawn.easy_async(
				{ "sh", "-c", string.format("echo %d > '/sys/class/backlight/%s/brightness'", new_raw, id) },
				function(_, _, _, exitcode)
					local next_delta = adj_step_queued[id]
					local next_cb = adj_step_cb_queued[id]
					adj_step_queued[id] = nil
					adj_step_cb_queued[id] = nil
					adj_step_in_progress[id] = nil
					if exitcode == 0 then
						entry.raw = new_raw
						entry.brightness = sysfs._raw_to_perc(new_raw, entry.max_brightness)
						cb(entry.brightness, new_raw)
					end
					if next_delta then
						self:adjust(id, next_delta, next_cb)
					end
				end
			)
		end,
	}
end

return setmetatable(sysfs, {
	__call = function(_, opts)
		return create(opts)
	end,
})
