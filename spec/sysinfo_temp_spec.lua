-- spec/sysinfo_temp_spec.lua
require("spec.support.awesome_mocks")

describe("sysinfo.temp module", function()
	local temp, captured_cb, mock_backend

	before_each(function()
		package.loaded["continuity.sysinfo.temp"] = nil
		captured_cb = nil
		mock_backend = {
			start = function(_self, cb)
				captured_cb = cb
			end,
			stop = function(_self) end,
		}
		temp = require("continuity.sysinfo.temp")
	end)

	local function push(s)
		captured_cb(s)
	end
	local function state(avg)
		return { zones = { ["/sys/thermal_zone0/temp"] = avg }, avg = avg }
	end

	it("state delivers nil before any push", function()
		temp.setup({ backend = mock_backend })
		local r = temp.state()
		assert.is_nil(r)
	end)

	it("subscriber called on push", function()
		temp.setup({ backend = mock_backend })
		local r
		temp:subscribe(function(s)
			r = s
		end)
		push(state(55))
		assert.equals(55, r.avg)
	end)

	it("subscriber called when avg changes", function()
		temp.setup({ backend = mock_backend })
		local calls = 0
		temp:subscribe(function()
			calls = calls + 1
		end)
		push(state(55))
		push(state(60))
		assert.equals(2, calls)
	end)

	it("subscriber called when a zone value changes", function()
		temp.setup({ backend = mock_backend })
		local calls = 0
		temp:subscribe(function()
			calls = calls + 1
		end)
		push({ zones = { z1 = 50, z2 = 60 }, avg = 55 })
		push({ zones = { z1 = 50, z2 = 65 }, avg = 57.5 })
		assert.equals(2, calls)
	end)

	it("stop() resets and allows re-setup", function()
		temp.setup({ backend = mock_backend })
		push(state(55))
		temp.stop()
		local r = temp.state()
		assert.is_nil(r)
		local new_cb
		temp.setup({ backend = {
			start = function(_, cb)
				new_cb = cb
			end,
			stop = function() end,
		} })
		local r2
		temp:subscribe(function(s)
			r2 = s
		end)
		new_cb(state(70))
		assert.equals(70, r2.avg)
	end)

	it("subscribe replays current state immediately if available", function()
		temp.setup({ backend = mock_backend })
		push(state(55))
		local replayed
		temp:subscribe(function(s)
			replayed = s
		end)
		assert.equals(55, replayed.avg)
	end)

	it("subscribe returns a callable unsubscribe function", function()
		temp.setup({ backend = mock_backend })
		local unsub = temp:subscribe(function() end)
		assert.is_function(unsub)
		unsub()
	end)

	it("state delivers state after a backend push", function()
		temp.setup({ backend = mock_backend })
		push(state(55))
		local r = temp.state()
		assert.equals(55, r.avg)
	end)

	it("unsubscribe stops delivery", function()
		temp.setup({ backend = mock_backend })
		local calls = 0
		local unsub = temp:subscribe(function()
			calls = calls + 1
		end)
		push(state(55))
		unsub()
		push(state(60))
		assert.equals(1, calls)
	end)

	it("second setup() logs a warning and is a no-op", function()
		local warned = false
		require("gears").debug.print_warning = function()
			warned = true
		end
		temp.setup({ backend = mock_backend })
		temp.setup({ backend = mock_backend })
		assert.is_true(warned)
	end)
end)
