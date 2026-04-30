-- spec/sysinfo_temp_sysfs_spec.lua
require("spec.support.awesome_mocks")

describe("temp.backends.sysfs", function()
	local sysfs, awful, gears_mod
	local captured_cbs, kill_called

	before_each(function()
		package.loaded["continuity.sysinfo.temp.backends.sysfs"] = nil
		kill_called = false
		captured_cbs = nil
		awful = require("awful")
		gears_mod = require("gears")
		gears_mod._created = {}
		awful.spawn.with_line_callback = function(_cmd, cbs)
			captured_cbs = cbs
			return 12345
		end
		awesome.kill = function(_pid, _sig)
			kill_called = true
		end
		sysfs = require("continuity.sysinfo.temp.backends.sysfs")
	end)

	local LINES = {
		"/sys/devices/virtual/thermal/thermal_zone0/temp:52000",
		"/sys/devices/virtual/thermal/thermal_zone1/temp:48000",
	}

	describe("_parse_temp_lines", function()
		it("converts raw values to °C (divide by 1000)", function()
			local s = sysfs._parse_temp_lines(LINES)
			assert.equals(52.0, s.zones["/sys/devices/virtual/thermal/thermal_zone0"])
			assert.equals(48.0, s.zones["/sys/devices/virtual/thermal/thermal_zone1"])
		end)

		it("computes avg as arithmetic mean", function()
			local s = sysfs._parse_temp_lines(LINES)
			assert.is_near(50.0, s.avg, 0.01)
		end)

		it("returns avg=0 for empty lines", function()
			local s = sysfs._parse_temp_lines({})
			assert.equals(0, s.avg)
			assert.is_table(s.zones)
		end)
	end)

	it("spawns process on start", function()
		local b = sysfs({ interval = 5 })
		b:start(function() end)
		assert.is_not_nil(captured_cbs)
	end)

	it("calls on_update with TempState on batch completion", function()
		local updates = {}
		local b = sysfs({ interval = 5 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		for _, l in ipairs(LINES) do
			captured_cbs.stdout(l)
		end
		captured_cbs.stdout("---")
		assert.equals(1, #updates)
		assert.is_number(updates[1].avg)
		assert.is_table(updates[1].zones)
	end)

	it("stop() kills the process", function()
		local b = sysfs({ interval = 5 })
		b:start(function() end)
		b:stop()
		assert.is_true(kill_called)
	end)

	it("process exit schedules retry timer", function()
		local b = sysfs({ interval = 5 })
		b:start(function() end)
		captured_cbs.exit()
		assert.equals(1, #gears_mod._created)
	end)

	it("stop() prevents exit callback from scheduling a retry", function()
		local b = sysfs({ interval = 5 })
		b:start(function() end)
		b:stop()
		captured_cbs.exit()
		assert.equals(0, #gears_mod._created)
	end)

	it("retry timer restarts the process", function()
		local spawn_count = 0
		awful.spawn.with_line_callback = function(_cmd, cbs)
			spawn_count = spawn_count + 1
			captured_cbs = cbs
			return spawn_count * 100
		end
		local b = sysfs({ interval = 5 })
		b:start(function() end)
		captured_cbs.exit()
		gears_mod._created[1]:fire()
		assert.equals(2, spawn_count)
	end)
end)
