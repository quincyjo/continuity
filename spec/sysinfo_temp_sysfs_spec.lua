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

	-- Two x86 zones: iwlwifi (disabled trip points) and x86_pkg_temp (disabled trip points).
	local LINES_X86 = {
		"/sys/class/thermal/thermal_zone0/temp:33000",
		"/sys/class/thermal/thermal_zone0/type:iwlwifi_1",
		"/sys/class/thermal/thermal_zone0/trip_point_0_type:passive",
		"/sys/class/thermal/thermal_zone0/trip_point_0_temp:-274000",
		"/sys/class/thermal/thermal_zone1/temp:54000",
		"/sys/class/thermal/thermal_zone1/type:x86_pkg_temp",
		"/sys/class/thermal/thermal_zone1/trip_point_0_type:passive",
		"/sys/class/thermal/thermal_zone1/trip_point_0_temp:-274000",
	}

	-- ARM zone with real trip points: passive < hot < critical.
	local LINES_ARM = {
		"/sys/class/thermal/thermal_zone0/temp:60000",
		"/sys/class/thermal/thermal_zone0/type:cpu-thermal",
		"/sys/class/thermal/thermal_zone0/trip_point_0_type:passive",
		"/sys/class/thermal/thermal_zone0/trip_point_0_temp:80000",
		"/sys/class/thermal/thermal_zone0/trip_point_1_type:hot",
		"/sys/class/thermal/thermal_zone0/trip_point_1_temp:85000",
		"/sys/class/thermal/thermal_zone0/trip_point_2_type:critical",
		"/sys/class/thermal/thermal_zone0/trip_point_2_temp:105000",
	}

	-- Zone with only passive trip points (no hot); lowest passive used as max.
	local LINES_PASSIVE_ONLY = {
		"/sys/class/thermal/thermal_zone0/temp:55000",
		"/sys/class/thermal/thermal_zone0/type:cpu-thermal",
		"/sys/class/thermal/thermal_zone0/trip_point_0_type:passive",
		"/sys/class/thermal/thermal_zone0/trip_point_0_temp:80000",
		"/sys/class/thermal/thermal_zone0/trip_point_1_type:passive",
		"/sys/class/thermal/thermal_zone0/trip_point_1_temp:90000",
		"/sys/class/thermal/thermal_zone0/trip_point_2_type:critical",
		"/sys/class/thermal/thermal_zone0/trip_point_2_temp:105000",
	}

	describe("_parse_sysfs_lines", function()
		it("produces a device per zone with name and label from type", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86)
			assert.equals(2, #s.devices)
			local names = {}
			for _, d in ipairs(s.devices) do
				names[d.name] = true
			end
			assert.is_true(names["iwlwifi_1"])
			assert.is_true(names["x86_pkg_temp"])
		end)

		it("name and label are both the zone type", function()
			local s = sysfs._parse_sysfs_lines(LINES_ARM)
			assert.equals(1, #s.devices)
			assert.equals("cpu-thermal", s.devices[1].name)
			assert.equals("cpu-thermal", s.devices[1].label)
		end)

		it("converts temp from millidegrees to Celsius", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86)
			local by_name = {}
			for _, d in ipairs(s.devices) do
				by_name[d.name] = d
			end
			assert.equals(33, by_name["iwlwifi_1"].temp)
			assert.equals(54, by_name["x86_pkg_temp"].temp)
		end)

		it("sensors is always empty (thermal has no sub-sensors)", function()
			local s = sysfs._parse_sysfs_lines(LINES_ARM)
			assert.same({}, s.devices[1].sensors)
		end)

		it("disabled trip points (-274°C) produce nil crit and max", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86)
			local by_name = {}
			for _, d in ipairs(s.devices) do
				by_name[d.name] = d
			end
			assert.is_nil(by_name["x86_pkg_temp"].crit)
			assert.is_nil(by_name["x86_pkg_temp"].max)
		end)

		it("parses critical trip point into crit", function()
			local s = sysfs._parse_sysfs_lines(LINES_ARM)
			assert.equals(105, s.devices[1].crit)
		end)

		it("parses hot trip point into max", function()
			local s = sysfs._parse_sysfs_lines(LINES_ARM)
			assert.equals(85, s.devices[1].max)
		end)

		it("uses lowest passive as max when hot is absent", function()
			local s = sysfs._parse_sysfs_lines(LINES_PASSIVE_ONLY)
			assert.equals(80, s.devices[1].max)
			assert.equals(105, s.devices[1].crit)
		end)

		it("selects cpu for known thermal label x86_pkg_temp", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86)
			assert.is_not_nil(s.cpu)
			assert.equals("x86_pkg_temp", s.cpu.name)
		end)

		it("selects cpu for known thermal label cpu-thermal", function()
			local s = sysfs._parse_sysfs_lines(LINES_ARM)
			assert.is_not_nil(s.cpu)
			assert.equals("cpu-thermal", s.cpu.name)
		end)

		it("cpu is nil when no known CPU zone is present", function()
			local lines = {
				"/sys/class/thermal/thermal_zone0/temp:33000",
				"/sys/class/thermal/thermal_zone0/type:iwlwifi_1",
			}
			local s = sysfs._parse_sysfs_lines(lines)
			assert.is_nil(s.cpu)
			assert.equals(1, #s.devices)
		end)

		it("cpu_device option overrides label matching", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86, "iwlwifi_1")
			assert.is_not_nil(s.cpu)
			assert.equals("iwlwifi_1", s.cpu.name)
		end)

		it("drops zones with bogus temp (above 200°C)", function()
			local lines = {
				"/sys/class/thermal/thermal_zone0/temp:300000",
				"/sys/class/thermal/thermal_zone0/type:bogus_zone",
			}
			local s = sysfs._parse_sysfs_lines(lines)
			assert.equals(0, #s.devices)
		end)

		it("drops zones with bogus temp (below -40°C)", function()
			local lines = {
				"/sys/class/thermal/thermal_zone0/temp:-50000",
				"/sys/class/thermal/thermal_zone0/type:bogus_zone",
			}
			local s = sysfs._parse_sysfs_lines(lines)
			assert.equals(0, #s.devices)
		end)

		it("returns empty devices for empty lines", function()
			local s = sysfs._parse_sysfs_lines({})
			assert.same({}, s.devices)
			assert.is_nil(s.cpu)
		end)

		it("exclude list removes matching devices", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86, nil, { "iwlwifi_1" })
			assert.equals(1, #s.devices)
			assert.equals("x86_pkg_temp", s.devices[1].name)
		end)

		it("exclude list supports Lua patterns", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86, nil, { "^iwlwifi" })
			assert.equals(1, #s.devices)
			assert.equals("x86_pkg_temp", s.devices[1].name)
		end)

		it("excluded cpu device results in nil cpu", function()
			local s = sysfs._parse_sysfs_lines(LINES_X86, nil, { "x86_pkg_temp" })
			assert.is_nil(s.cpu)
			assert.equals(1, #s.devices)
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
		for _, l in ipairs(LINES_X86) do
			captured_cbs.stdout(l)
		end
		captured_cbs.stdout("---")
		assert.equals(1, #updates)
		assert.is_table(updates[1].devices)
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
