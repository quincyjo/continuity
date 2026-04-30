-- spec/sysinfo_bat_udevadm_spec.lua
require("spec.support.awesome_mocks")

describe("bat.backends.udevadm", function()
	local udevadm, awful, gears_mod
	local wlc_cbs, easy_async_cb, kill_called

	before_each(function()
		package.loaded["continuity.sysinfo.bat.backends.udevadm"] = nil
		kill_called = false
		wlc_cbs = nil
		easy_async_cb = nil
		awful = require("awful")
		gears_mod = require("gears")
		gears_mod._created = {}
		awful.spawn.with_line_callback = function(_cmd, cbs)
			wlc_cbs = cbs
			return 12345
		end
		awesome.kill = function(_pid, _sig)
			kill_called = true
		end
		awful.spawn.easy_async = function(_cmd, cb)
			easy_async_cb = cb
		end
		udevadm = require("continuity.sysinfo.bat.backends.udevadm")
	end)

	local SYSFS_OUTPUT = table.concat({
		"===:AC0",
		"POWER_SUPPLY_NAME=AC0",
		"POWER_SUPPLY_TYPE=Mains",
		"POWER_SUPPLY_ONLINE=1",
		"===:BAT0",
		"POWER_SUPPLY_NAME=BAT0",
		"POWER_SUPPLY_TYPE=Battery",
		"POWER_SUPPLY_STATUS=Discharging",
		"POWER_SUPPLY_CAPACITY=85",
		"POWER_SUPPLY_ENERGY_NOW=42500000",
		"POWER_SUPPLY_ENERGY_FULL=50000000",
		"POWER_SUPPLY_ENERGY_FULL_DESIGN=56000000",
		"POWER_SUPPLY_POWER_NOW=15000000",
		"POWER_SUPPLY_CHARGE_CONTROL_START_THRESHOLD=20",
		"POWER_SUPPLY_CHARGE_CONTROL_END_THRESHOLD=80",
	}, "\n") .. "\n"

	describe("_parse_bat_output", function()
		it("parses AC online status", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			assert.equals("1", raw.ac["AC0"])
		end)

		it("ignores non-Mains non-Battery devices", function()
			local extra = SYSFS_OUTPUT
				.. table.concat({
					"===:USB0",
					"POWER_SUPPLY_NAME=USB0",
					"POWER_SUPPLY_TYPE=USB",
					"POWER_SUPPLY_ONLINE=1",
				}, "\n")
				.. "\n"
			local raw = udevadm._parse_bat_output(extra)
			assert.is_nil(raw.ac["USB0"])
			assert.is_nil(raw.batteries["USB0"])
		end)

		it("parses battery fields (strips POWER_SUPPLY_ prefix, lowercases)", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			assert.equals("Discharging", raw.batteries["BAT0"].status)
			assert.equals("85", raw.batteries["BAT0"].capacity)
			assert.equals("42500000", raw.batteries["BAT0"].energy_now)
		end)

		it("parses charge_control_start_threshold", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			assert.equals("20", raw.batteries["BAT0"].charge_control_start_threshold)
		end)

		it("parses charge_control_end_threshold", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			assert.equals("80", raw.batteries["BAT0"].charge_control_end_threshold)
		end)
	end)

	describe("_compute_bat_state", function()
		it("sets ac_online true when any AC device is '1'", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			raw.batteries["BAT0"].status = "Charging"
			local s = udevadm._compute_bat_state(raw)
			assert.is_true(s.ac_online)
		end)

		it("converts energy_now from µWh to Wh", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			local s = udevadm._compute_bat_state(raw)
			assert.is_near(42.5, s.energy_now, 0.01)
		end)

		it("converts power_now from µW to W", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			local s = udevadm._compute_bat_state(raw)
			assert.is_near(15.0, s.power_now, 0.01)
		end)

		it("derives power from current_now * voltage_now when power_now absent", function()
			-- Simulates charge_* batteries (e.g. ThinkPad) that expose current_now/voltage_now
			-- instead of power_now. 825000 µA * 12000000 µV = 9.9 W
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			raw.batteries["BAT0"].power_now = nil
			raw.batteries["BAT0"].current_now = "825000" -- µA
			raw.batteries["BAT0"].voltage_now = "12000000" -- µV
			local s = udevadm._compute_bat_state(raw)
			assert.is_near(9.9, s.power_now, 0.01)
		end)

		it("computes capacity health %", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			local s = udevadm._compute_bat_state(raw)
			assert.is_near(50.0 / 56.0 * 100, s.capacity, 1)
		end)

		it("populates batteries array", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			local s = udevadm._compute_bat_state(raw)
			assert.equals(1, #s.batteries)
			assert.equals("BAT0", s.batteries[1].name)
		end)

		it("exposes charge_control_start_threshold on BatteryState as a number", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			local s = udevadm._compute_bat_state(raw)
			assert.equals(20, s.batteries[1].charge_control_start_threshold)
		end)

		it("exposes charge_control_end_threshold on BatteryState as a number", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			local s = udevadm._compute_bat_state(raw)
			assert.equals(80, s.batteries[1].charge_control_end_threshold)
		end)

		it("charge_controlled is false when perc (85) is above end_threshold (80)", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			local s = udevadm._compute_bat_state(raw)
			assert.is_false(s.charge_controlled)
		end)

		it("charge_controlled is true when perc is within [start_threshold, end_threshold]", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			raw.batteries["BAT0"].capacity = "75" -- within [20, 80]
			local s = udevadm._compute_bat_state(raw)
			assert.is_true(s.charge_controlled)
		end)

		it("charge_controlled is false when threshold fields are absent", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			raw.batteries["BAT0"].charge_control_start_threshold = nil
			raw.batteries["BAT0"].charge_control_end_threshold = nil
			local s = udevadm._compute_bat_state(raw)
			assert.is_false(s.charge_controlled)
		end)

		it("charge_controlled is true when any battery is within its window", function()
			local raw = udevadm._parse_bat_output(SYSFS_OUTPUT)
			raw.batteries["BAT0"].capacity = "75" -- BAT0 within [20, 80]
			raw.batteries["BAT1"] = {
				type = "Battery",
				status = "Charging",
				capacity = "95",
				charge_control_start_threshold = "20",
				charge_control_end_threshold = "80",
				energy_now = "47500000",
				energy_full = "50000000",
				energy_full_design = "56000000",
				power_now = "10000000",
				voltage_now = "0",
			}
			local s = udevadm._compute_bat_state(raw)
			assert.is_true(s.charge_controlled)
		end)
	end)

	it("triggers an initial sysfs read on start", function()
		local b = udevadm({})
		b:start(function() end)
		assert.is_not_nil(easy_async_cb)
	end)

	it("calls on_update when initial read succeeds", function()
		local updates = {}
		local b = udevadm({})
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		assert.equals(1, #updates)
		assert.is_number(updates[1].perc)
	end)

	it("does not call on_update when initial read fails", function()
		local updates = {}
		local b = udevadm({})
		b:start(function(s)
			updates[#updates + 1] = s
		end)
		easy_async_cb("", "", "", 1)
		assert.equals(0, #updates)
	end)

	it("udevadm monitor event triggers a sysfs re-read", function()
		local b = udevadm({})
		b:start(function() end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		easy_async_cb = nil
		wlc_cbs.stdout("UDEV  [12345.678] change   /devices/.../power_supply/AC0 (power_supply)")
		assert.is_not_nil(easy_async_cb)
	end)

	it("poll=true creates a timer with default 30s interval", function()
		local b = udevadm({ poll = true })
		b:start(function() end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		local poll_timers = {}
		for _, t in ipairs(gears_mod._created) do
			if t._opts.timeout == 30 then
				poll_timers[#poll_timers + 1] = t
			end
		end
		assert.equals(1, #poll_timers)
	end)

	it("poll=60 creates a timer with 60s interval", function()
		local b = udevadm({ poll = 60 })
		b:start(function() end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		local found = false
		for _, t in ipairs(gears_mod._created) do
			if t._opts.timeout == 60 then
				found = true
			end
		end
		assert.is_true(found)
	end)

	it("poll=false creates no poll timer", function()
		local b = udevadm({ poll = false })
		b:start(function() end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		assert.equals(0, #gears_mod._created)
	end)

	it("stop() kills the monitor process and stops poll timer", function()
		local b = udevadm({ poll = true })
		b:start(function() end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		b:stop()
		assert.is_true(kill_called)
		local poll_stopped = false
		for _, t in ipairs(gears_mod._created) do
			if t._opts.timeout == 30 and t.stopped then
				poll_stopped = true
			end
		end
		assert.is_true(poll_stopped)
	end)

	it("monitor exit schedules retry", function()
		local b = udevadm({ poll = false })
		b:start(function() end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		wlc_cbs.exit()
		assert.equals(1, #gears_mod._created)
		assert.equals(10, gears_mod._created[1]._opts.timeout)
	end)

	it("stop() prevents exit callback from scheduling a retry", function()
		local b = udevadm({ poll = false })
		b:start(function() end)
		easy_async_cb(SYSFS_OUTPUT, "", "", 0)
		b:stop()
		wlc_cbs.exit()
		assert.equals(0, #gears_mod._created)
	end)
end)
