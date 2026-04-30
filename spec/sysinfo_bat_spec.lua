-- spec/sysinfo_bat_spec.lua
require("spec.support.awesome_mocks")

describe("sysinfo.bat module", function()
	local bat, captured_cb, mock_backend

	before_each(function()
		package.loaded["continuity.sysinfo.bat"] = nil
		captured_cb = nil
		mock_backend = {
			start = function(self, cb)
				captured_cb = cb
			end,
			stop = function(self) end,
		}
		bat = require("continuity.sysinfo.bat")
	end)

	local function push(s)
		captured_cb(s)
	end

	local function state(perc, status)
		return {
			status = status or "Discharging",
			ac_online = false,
			perc = perc,
			energy_now = perc * 0.5,
			energy_full = 50.0,
			energy_design = 56.0,
			power_now = 15.0,
			capacity = 89,
			time_remaining = (perc * 0.5 / 15.0) * 3600,
			time_until_full = nil,
			batteries = {
				{
					name = "BAT0",
					status = status or "Discharging",
					perc = perc,
					energy_now = perc * 0.5,
					energy_full = 50.0,
				},
			},
		}
	end

	it("state delivers nil before any push", function()
		bat.setup({ backend = mock_backend })
		local r = bat.state()
		assert.is_nil(r)
	end)

	it("subscriber called on push", function()
		bat.setup({ backend = mock_backend })
		local r
		bat:subscribe(function(s)
			r = s
		end)
		push(state(80))
		assert.equals(80, r.perc)
	end)

	it("subscriber called when perc changes", function()
		bat.setup({ backend = mock_backend })
		local calls = 0
		bat:subscribe(function()
			calls = calls + 1
		end)
		push(state(80))
		push(state(79))
		assert.equals(2, calls)
	end)

	it("subscriber called when status changes", function()
		bat.setup({ backend = mock_backend })
		local calls = 0
		bat:subscribe(function()
			calls = calls + 1
		end)
		push(state(80, "Discharging"))
		push(state(80, "Charging"))
		assert.equals(2, calls)
	end)

	it("stop() resets and allows re-setup", function()
		bat.setup({ backend = mock_backend })
		push(state(80))
		bat.stop()
		local r = bat.state()
		assert.is_nil(r)
		local new_cb
		bat.setup({ backend = {
			start = function(_, cb)
				new_cb = cb
			end,
			stop = function() end,
		} })
		local r2
		bat:subscribe(function(s)
			r2 = s
		end)
		new_cb(state(50))
		assert.equals(50, r2.perc)
	end)

	it("subscribe replays current state immediately if available", function()
		bat.setup({ backend = mock_backend })
		push(state(80))
		local replayed
		bat:subscribe(function(s)
			replayed = s
		end)
		assert.equals(80, replayed.perc)
	end)

	it("subscribe returns a callable unsubscribe function", function()
		bat.setup({ backend = mock_backend })
		local unsub = bat:subscribe(function() end)
		assert.is_function(unsub)
		unsub()
	end)

	it("state delivers state after a backend push", function()
		bat.setup({ backend = mock_backend })
		push(state(80))
		local r = bat.state()
		assert.equals(80, r.perc)
	end)

	it("unsubscribe stops delivery", function()
		bat.setup({ backend = mock_backend })
		local calls = 0
		local unsub = bat:subscribe(function()
			calls = calls + 1
		end)
		push(state(80))
		unsub()
		push(state(79))
		assert.equals(1, calls)
	end)

	it("second setup() logs a warning and is a no-op", function()
		local warned = false
		require("gears").debug.print_warning = function()
			warned = true
		end
		bat.setup({ backend = mock_backend })
		bat.setup({ backend = mock_backend })
		assert.is_true(warned)
	end)

	it("time_remaining returns nil before any push", function()
		bat.setup({ backend = mock_backend })
		assert.is_nil(bat.time_remaining())
	end)

	it("time_remaining returns nil when not Discharging", function()
		bat.setup({ backend = mock_backend })
		push(state(80, "Charging"))
		assert.is_nil(bat.time_remaining())
	end)

	it("time_remaining computes seconds from energy_now / power_now", function()
		bat.setup({ backend = mock_backend })
		-- energy_now = 40 * 0.5 = 20, power_now = 15 -> 20/15 * 3600 = 4800s
		push(state(40))
		local expected = math.floor((40 * 0.5 / 15.0) * 3600)
		assert.is_near(expected, bat.time_remaining(), 1)
	end)

	it("time_until_full returns nil before any push", function()
		bat.setup({ backend = mock_backend })
		assert.is_nil(bat.time_until_full())
	end)

	it("time_until_full returns nil when not Charging", function()
		bat.setup({ backend = mock_backend })
		push(state(80, "Discharging"))
		assert.is_nil(bat.time_until_full())
	end)

	it("time_until_full computes seconds from (energy_full - energy_now) / power_now", function()
		bat.setup({ backend = mock_backend })
		-- perc=80: energy_now=40, energy_full=50, power_now=15 -> 10/15*3600=2400s
		local s = state(80, "Charging")
		push(s)
		local expected = math.floor(((s.energy_full - s.energy_now) / s.power_now) * 3600)
		assert.is_near(expected, bat.time_until_full(), 1)
	end)
end)
