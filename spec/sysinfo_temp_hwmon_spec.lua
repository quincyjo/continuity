-- spec/sysinfo_temp_hwmon_spec.lua
require("spec.support.awesome_mocks")

describe("temp.backends.hwmon", function()
	local hwmon, awful, gears_mod
	local captured_cbs, kill_called

	before_each(function()
		package.loaded["continuity.sysinfo.temp.backends.hwmon"] = nil
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
		hwmon = require("continuity.sysinfo.temp.backends.hwmon")
	end)

	-- coretemp: Package id 0 (temp1) + Core 0..1 (temp2..3)
	local LINES_CORETEMP = {
		"/sys/class/hwmon/hwmon4/name:coretemp",
		"/sys/class/hwmon/hwmon4/temp1_input:54000",
		"/sys/class/hwmon/hwmon4/temp1_label:Package id 0",
		"/sys/class/hwmon/hwmon4/temp1_crit:100000",
		"/sys/class/hwmon/hwmon4/temp1_max:100000",
		"/sys/class/hwmon/hwmon4/temp2_input:51000",
		"/sys/class/hwmon/hwmon4/temp2_label:Core 0",
		"/sys/class/hwmon/hwmon4/temp2_crit:100000",
		"/sys/class/hwmon/hwmon4/temp2_max:100000",
		"/sys/class/hwmon/hwmon4/temp3_input:54000",
		"/sys/class/hwmon/hwmon4/temp3_label:Core 1",
		"/sys/class/hwmon/hwmon4/temp3_crit:100000",
		"/sys/class/hwmon/hwmon4/temp3_max:100000",
	}

	-- nvme: Composite (temp1) with real crit, sentinel max; Sensor 1 (temp2) with sentinel max.
	local LINES_NVME = {
		"/sys/class/hwmon/hwmon3/name:nvme",
		"/sys/class/hwmon/hwmon3/temp1_input:35850",
		"/sys/class/hwmon/hwmon3/temp1_label:Composite",
		"/sys/class/hwmon/hwmon3/temp1_crit:84850",
		"/sys/class/hwmon/hwmon3/temp1_max:65261850",
		"/sys/class/hwmon/hwmon3/temp2_input:35850",
		"/sys/class/hwmon/hwmon3/temp2_label:Sensor 1",
		"/sys/class/hwmon/hwmon3/temp2_max:65261850",
	}

	-- AC adapter: hwmon entry with no temp files.
	local LINES_AC = {
		"/sys/class/hwmon/hwmon0/name:AC",
	}

	-- iwlwifi: temp input but no label file.
	local LINES_IWLWIFI = {
		"/sys/class/hwmon/hwmon5/name:iwlwifi_1",
		"/sys/class/hwmon/hwmon5/temp1_input:33000",
	}

	describe("_parse_hwmon_lines", function()
		it("produces a device per hwmon entry with temp sensors", function()
			local lines = {}
			for _, l in ipairs(LINES_CORETEMP) do
				lines[#lines + 1] = l
			end
			for _, l in ipairs(LINES_AC) do
				lines[#lines + 1] = l
			end
			local s = hwmon._parse_hwmon_lines(lines)
			assert.equals(1, #s.devices)
			assert.equals("coretemp", s.devices[1].name)
		end)

		it("skips hwmon entries with no temp_input files", function()
			local s = hwmon._parse_hwmon_lines(LINES_AC)
			assert.equals(0, #s.devices)
		end)

		it("temp1 becomes the device-level entry", function()
			local s = hwmon._parse_hwmon_lines(LINES_CORETEMP)
			assert.equals(1, #s.devices)
			local d = s.devices[1]
			assert.equals("Package id 0", d.label)
			assert.equals(54, d.temp)
			assert.equals(100, d.crit)
			assert.equals(100, d.max)
		end)

		it("temp2..N become sensors on the device", function()
			local s = hwmon._parse_hwmon_lines(LINES_CORETEMP)
			local d = s.devices[1]
			assert.equals(2, #d.sensors)
			assert.equals("Core 0", d.sensors[1].label)
			assert.equals(51, d.sensors[1].temp)
			assert.equals("Core 1", d.sensors[2].label)
			assert.equals(54, d.sensors[2].temp)
		end)

		it("sentinel max (0xFFFF Kelvin) is filtered to nil", function()
			local s = hwmon._parse_hwmon_lines(LINES_NVME)
			local d = s.devices[1]
			assert.equals(35.85, d.temp)
			assert.equals(84.85, d.crit)
			assert.is_nil(d.max)
		end)

		it("sentinel max on sub-sensor is filtered to nil", function()
			local s = hwmon._parse_hwmon_lines(LINES_NVME)
			local d = s.devices[1]
			assert.equals(1, #d.sensors)
			assert.is_nil(d.sensors[1].max)
		end)

		it("absent label is nil (not an error)", function()
			local s = hwmon._parse_hwmon_lines(LINES_IWLWIFI)
			assert.equals(1, #s.devices)
			assert.is_nil(s.devices[1].label)
		end)

		it("selects cpu for known hwmon label Package id 0", function()
			local s = hwmon._parse_hwmon_lines(LINES_CORETEMP)
			assert.is_not_nil(s.cpu)
			assert.equals("coretemp", s.cpu.name)
		end)

		it("cpu is nil when no known CPU label is present", function()
			local s = hwmon._parse_hwmon_lines(LINES_NVME)
			assert.is_nil(s.cpu)
			assert.equals(1, #s.devices)
		end)

		it("cpu_device option overrides label matching", function()
			local s = hwmon._parse_hwmon_lines(LINES_NVME, "nvme")
			assert.is_not_nil(s.cpu)
			assert.equals("nvme", s.cpu.name)
		end)

		it("drops devices with bogus temp1_input (above 200°C)", function()
			local lines = {
				"/sys/class/hwmon/hwmon9/name:bad_sensor",
				"/sys/class/hwmon/hwmon9/temp1_input:300000",
				"/sys/class/hwmon/hwmon9/temp1_label:Hot stuff",
			}
			local s = hwmon._parse_hwmon_lines(lines)
			assert.equals(0, #s.devices)
		end)

		it("returns empty devices for empty lines", function()
			local s = hwmon._parse_hwmon_lines({})
			assert.same({}, s.devices)
			assert.is_nil(s.cpu)
		end)

		it("multiple hwmon devices are all included", function()
			local lines = {}
			for _, l in ipairs(LINES_CORETEMP) do
				lines[#lines + 1] = l
			end
			for _, l in ipairs(LINES_NVME) do
				lines[#lines + 1] = l
			end
			local s = hwmon._parse_hwmon_lines(lines)
			assert.equals(2, #s.devices)
		end)

		it("exclude list removes matching devices", function()
			local lines = {}
			for _, l in ipairs(LINES_CORETEMP) do
				lines[#lines + 1] = l
			end
			for _, l in ipairs(LINES_NVME) do
				lines[#lines + 1] = l
			end
			local s = hwmon._parse_hwmon_lines(lines, nil, { "nvme" })
			assert.equals(1, #s.devices)
			assert.equals("coretemp", s.devices[1].name)
		end)

		it("exclude list supports Lua patterns", function()
			local lines = {}
			for _, l in ipairs(LINES_CORETEMP) do
				lines[#lines + 1] = l
			end
			for _, l in ipairs(LINES_NVME) do
				lines[#lines + 1] = l
			end
			local s = hwmon._parse_hwmon_lines(lines, nil, { "^nv" })
			assert.equals(1, #s.devices)
			assert.equals("coretemp", s.devices[1].name)
		end)

		it("excluded cpu device results in nil cpu", function()
			local s = hwmon._parse_hwmon_lines(LINES_CORETEMP, nil, { "coretemp" })
			assert.is_nil(s.cpu)
			assert.equals(0, #s.devices)
		end)
	end)

	it("spawns process on start", function()
		local b = hwmon({ interval = 5 })
		b:start(function() end)
		assert.is_not_nil(captured_cbs)
	end)

	it("calls on_update with TempState on batch completion", function()
		local updates = {}
		local b = hwmon({ interval = 5 })
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		for _, l in ipairs(LINES_CORETEMP) do
			captured_cbs.stdout(l)
		end
		captured_cbs.stdout("---")
		assert.equals(1, #updates)
		assert.is_table(updates[1].devices)
	end)

	it("stop() kills the process", function()
		local b = hwmon({ interval = 5 })
		b:start(function() end)
		b:stop()
		assert.is_true(kill_called)
	end)
end)
