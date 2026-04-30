local awful = require("awful")
local gears = require("gears")
local Process = require("continuity.util.process")

---@class XBacklightOptions
---@field interval? integer  -- polling interval in seconds, default 5
---@field time?     integer  -- transition duration in milliseconds, default 100
---@field steps?    integer  -- transition step count, default 20

local xbacklight_mod = {}

---@param opts? XBacklightOptions
---@return BacklightBackend
local function create(opts)
	opts = opts or {}
	local interval = opts.interval or 5
	local time = opts.time or 100
	local steps = opts.steps or 20

	local callbacks = nil
	local last_brightness = nil

	local proc = Process({
		name = "backlight.xbacklight",
		cmd = "xbacklight -get",
		interval = interval,
		stdout = function(line)
			local value = tonumber(line)
			if not value then
				return
			end
			local brightness = math.floor(value + 0.5)
			if brightness == last_brightness then
				return
			end
			last_brightness = brightness
			if callbacks then
				callbacks.on_change("default", brightness)
			end
		end,
	})

	local adj_in_progress = false
	local adj_queued = nil
	local adj_cb_queued = nil

	return {
		start = function(_, cbs)
			callbacks = cbs
			awful.spawn.easy_async({ "xbacklight", "-get" }, function(stdout, _, _, exitcode)
				if exitcode ~= 0 then
					gears.debug.print_warning(
						"backlight.xbacklight: xbacklight -get failed; check RandR/backlight support"
					)
					return
				end
				local value = tonumber(stdout)
				if not value then
					gears.debug.print_warning("backlight.xbacklight: unexpected output from xbacklight -get")
					return
				end
				local brightness = math.floor(value + 0.5)
				last_brightness = brightness
				if callbacks then
					callbacks.on_device_added({
						id = "default",
						kind = "display",
						brightness = brightness,
					})
				end
				proc:start()
			end)
		end,
		stop = function(_)
			proc:stop()
			callbacks = nil
		end,
		adjust_perc = function(self, _id, delta, cb) -- luacheck: ignore 212
			if delta == 0 then
				return
			end
			if adj_in_progress then
				adj_queued = delta
				adj_cb_queued = cb
				return
			end
			adj_in_progress = true
			local flag = delta > 0 and "-inc" or "-dec"
			awful.spawn.easy_async({
				"xbacklight",
				flag,
				tostring(math.abs(delta)),
				"-time",
				tostring(time),
				"-steps",
				tostring(steps),
			}, function(_, _, _, exitcode)
				local next_delta = adj_queued
				local next_cb = adj_cb_queued
				adj_queued = nil
				adj_cb_queued = nil
				adj_in_progress = false
				if exitcode == 0 then
					awful.spawn.easy_async({ "xbacklight", "-get" }, function(out, _, _, ec)
						if ec == 0 then
							local value = tonumber(out)
							if not value then
								return
							end
							local brightness = math.floor(value + 0.5)
							last_brightness = brightness
							cb(brightness)
						end
					end)
				end
				if next_delta then
					self:adjust_perc("default", next_delta, next_cb)
				end
			end)
		end,
		set_perc = function(_, _id, pct, cb) -- luacheck: ignore 212
			pct = math.max(0, math.min(100, pct))
			awful.spawn.easy_async({
				"xbacklight",
				"-set",
				tostring(pct),
				"-time",
				tostring(time),
				"-steps",
				tostring(steps),
			}, function()
				awful.spawn.easy_async({
					"xbacklight",
					"-get",
				}, function(out, _, _, exitcode)
					if exitcode == 0 then
						local value = tonumber(out)
						if not value then
							return
						end
						local brightness = math.floor(value + 0.5)
						last_brightness = brightness
						cb(brightness)
					end
				end)
			end)
		end,
	}
end

return setmetatable(xbacklight_mod, {
	__call = function(_, opts)
		return create(opts)
	end,
})
