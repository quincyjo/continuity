local awful = require("awful")
local Process = require("continuity.util.process")

-- TODO: Make xbacklight and acpilight accept no time.

---@class AcpilightOptions
---@field interval? integer  -- polling interval in seconds, default 5
---@field time?     integer  -- transition duration in milliseconds, default 100
---@field fps?      integer  -- transition steps in fps, default 30
---@field filter?   fun(name: string): boolean  -- override default (video|backlight) pattern

local acpilight = {}

---@param name string
---@return boolean
function acpilight._default_filter(name)
	local lower = name:lower()
	return lower:match("video") ~= nil or lower:match("backlight") ~= nil
end

---@param name string
---@return BacklightKind
function acpilight._kind_from_name(name)
	local lower = name:lower()
	if lower:match("kbd") or lower:match("keyboard") then
		return "keyboard"
	end
	return "display"
end

---@param line string
---@return string|nil, integer|nil
function acpilight._parse_line(line)
	local name, val = line:match("^(.+):([%d%.]+)$")
	if name and val then
		local brightness = tonumber(val)
		if brightness then
			return name, math.floor(brightness)
		end
	end
	return nil, nil
end

---@param raw   integer  The raw brightness value.
---@param steps integer The number of brightness steps.
---@return number The brightness value as a percentage from 0 to 100.
function acpilight._legacy_raw_to_perc(raw, steps)
	return raw >= steps - 1 and 100 or math.max(0, raw * 100 / (steps - 1))
end

---@param raw   integer  The raw brightness value.
---@param steps integer The number of brightness steps.
---@return number The brightness value as a percentage from 0 to 100.
function acpilight._raw_to_perc(raw, steps)
	if raw >= steps - 1 then
		return 100
	end
	if raw <= 0 then
		return 0
	end
	return math.floor(raw / steps * 100 + 0.5)
end

--- Legacy brightness percent to raw brightness value. This implements the
--- incorrect conversion of xbacklight and acpilight.
---@param perc  number  The brightness value as a percentage from 0 to 100.
---@param steps integer The number of brightness steps.
---@return integer
function acpilight._legacy_perc_to_raw(perc, steps)
	return math.floor(perc / 100 * (steps - 1) + 0.5)
end

--- Correct brightness percent to raw brightness value.
---@param perc  number  The brightness value as a percentage from 0 to 100.
---@param steps integer The number of brightness steps.
---@return integer
function acpilight._perc_to_raw(perc, steps)
	if perc >= 100 then
		return steps - 1
	end
	return math.min(steps - 1, math.floor(perc / 100 * steps + 0.5))
end

---@param opts? AcpilightOptions
---@return BacklightBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 5
	local time = opts.time or 100
	local fps = opts.fps or 30
	local filter = opts.filter or acpilight._default_filter

	local callbacks = nil
	local known = {}
	local buf = {}

	---@type table<string, integer>
	local adj_queued = {}
	---@type table<string, function>
	local adj_cb_queued = {}
	---@type table<string, boolean>
	local adj_in_progress = {}

	---@type table<string, integer>
	local set_queued = {}
	---@type table<string, function>
	local set_cb_queued = {}
	---@type table<string, boolean>
	local set_in_progress = {}

	---@param name string The name of the backlight device.
	---@param brightness number The brightness value as a percentage from 0 to 100.
	---@return integer|nil The raw brightness value, or nil if the device is not known or has no steps.
	local function perc_to_raw(name, brightness)
		if not known[name] or not known[name].steps then
			return nil
		end
		return acpilight._legacy_perc_to_raw(brightness, known[name].steps)
	end

	local proc = Process({
		name = "backlight.acpilight",
		cmd = {
			[[xbacklight -list | while IFS= read -r ctrl; do
  brightness=$(xbacklight -get -ctrl "$ctrl" 2>/dev/null)
  [ -n "$brightness" ] && printf '%s:%s\n' "$ctrl" "$brightness"
done]],
			"echo '---'",
		},
		interval = interval,
		stdout = function(line)
			if line ~= "---" then
				local name, brightness = acpilight._parse_line(line)
				if name and filter(name) then
					buf[#buf + 1] = { name = name, brightness = brightness }
				end
				return
			end

			local seen = {}
			for _, entry in ipairs(buf) do
				seen[entry.name] = entry.brightness
			end
			buf = {}

			for name, brightness in pairs(seen) do
				if not known[name] then
					local kind = acpilight._kind_from_name(name)
					known[name] = { pending = true, kind = kind }
					awful.spawn.easy_async({ "xbacklight", "-get-steps", "-ctrl", name }, function(stdout, _, _, ec)
						if not known[name] then
							return
						end
						local steps = ec == 0 and tonumber(stdout) or nil
						known[name] = { kind = kind, brightness = brightness, steps = steps }
						if callbacks then
							callbacks.on_device_added({
								id = name,
								kind = kind,
								brightness = brightness,
								steps = steps,
								raw = perc_to_raw(name, brightness),
							})
						end
					end)
				elseif not known[name].pending and brightness ~= known[name].brightness then
					local raw = perc_to_raw(name, brightness)
					known[name].brightness = brightness
					known[name].raw = raw
					if callbacks then
						callbacks.on_change(name, brightness, raw)
					end
				end
			end

			local removed = {}
			for name in pairs(known) do
				if not seen[name] then
					removed[#removed + 1] = name
				end
			end
			for _, name in ipairs(removed) do
				local was_pending = known[name] and known[name].pending
				known[name] = nil
				if callbacks and not was_pending then
					callbacks.on_device_removed(name)
				end
			end
		end,
		exit = function()
			buf = {}
		end,
	})

	local backend = {
		start = function(_, cbs)
			callbacks = cbs
			proc:start()
		end,
		stop = function(_)
			proc:stop()
			callbacks = nil
		end,
		-- TODO: Extend the same guards to the other backends.
		adjust_perc = function(self, id, delta, cb)
			if delta == 0 then
				return
			end
			if adj_in_progress[id] then
				adj_queued[id] = delta
				adj_cb_queued[id] = cb
				return
			end
			adj_in_progress[id] = true
			local flag = delta > 0 and "-inc" or "-dec"
			awful.spawn.easy_async({
				"xbacklight",
				flag,
				tostring(math.abs(delta)),
				"-ctrl",
				id,
				"-time",
				tostring(time),
				"-fps",
				tostring(fps),
			}, function(_, _, _, exitcode)
				if exitcode == 0 then
					adj_in_progress[id] = nil
					if adj_queued[id] then
						local next_adjustment = adj_queued[id]
						local next_cb = adj_cb_queued[id]
						adj_queued[id] = nil
						adj_cb_queued[id] = nil
						local perc = known[id].brightness + delta
						perc = perc > 100 and 100 or perc < 0 and 0 or perc
						known[id].brightness = perc
						known[id].raw = perc_to_raw(id, perc)
						cb(perc, known[id].raw)
						self:adjust_perc(id, next_adjustment, next_cb)
					else
						awful.spawn.easy_async({
							"xbacklight",
							"-get",
							"-ctrl",
							id,
						}, function(stdout, _, _, ec)
							if not adj_in_progress[id] and ec == 0 then
								local perc = tonumber(stdout)
								if perc then
									cb(perc, perc_to_raw(id, perc))
								end
							end
						end)
					end
				end
			end)
		end,
		set_perc = function(self, id, perc, cb)
			perc = math.max(0, math.min(100, perc))
			if set_in_progress[id] then
				set_queued[id] = perc
				set_cb_queued[id] = cb
				return
			end
			set_in_progress[id] = true
			awful.spawn.easy_async({
				"xbacklight",
				"-set",
				tostring(perc),
				"-ctrl",
				id,
				"-time",
				tostring(time),
				"-fps",
				tostring(fps),
			}, function(_, _, _, exitcode)
				set_in_progress[id] = nil
				if exitcode == 0 then
					if set_queued[id] then
						local next_set = set_queued[id]
						local next_cb = set_cb_queued[id]
						set_queued[id] = nil
						set_cb_queued[id] = nil
						self:set_perc(id, next_set, next_cb)
					else
						awful.spawn.easy_async({
							"xbacklight",
							"-get",
							"-ctrl",
							id,
						}, function(stdout, _, _, ec)
							if not set_in_progress[id] and ec == 0 then
								local current = tonumber(stdout)
								if current then
									cb(current, perc_to_raw(id, current))
								end
							end
						end)
					end
				end
			end)
		end,
		-- NOTE: acpilight has the miscalculated perc bug, using max instead of steps,
		-- so we do that to keep it aligned to its percent steps calculation.
		set = function(self, id, step, cb)
			local entry = known[id]
			if not entry or entry.pending or not entry.steps then
				return
			end
			self:set_perc(id, acpilight._legacy_raw_to_perc(step, entry.steps), cb)
		end,
		adjust = function(self, id, delta, cb)
			if delta == 0 then
				return
			end
			local entry = known[id]
			if not entry or entry.pending or not entry.steps then
				return
			end
			self:adjust_perc(id, delta * 100 / (entry.steps - 1), cb)
		end,
	}

	return backend
end

return setmetatable(acpilight, {
	__call = function(_, opts)
		return create(opts)
	end,
})
