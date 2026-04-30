-- spec/sysinfo_mem_spec.lua
require("spec.support.awesome_mocks")

describe("sysinfo.mem module", function()
	local mem
	local captured_cb, mock_backend

	before_each(function()
		package.loaded["continuity.sysinfo.mem"] = nil
		captured_cb = nil
		mock_backend = {
			start = function(_self, cb)
				captured_cb = cb
			end,
			stop = function(_self) end,
		}
		mem = require("continuity.sysinfo.mem")
	end)

	local function push(s)
		captured_cb(s)
	end
	local function state(used)
		return {
			total = 16000,
			used = used,
			free = 16000 - used,
			buffers = 0,
			cached = 0,
			perc = math.floor(used / 16000 * 100),
			swap_total = 0,
			swap_used = 0,
			swap_free = 0,
		}
	end

	it("state delivers nil before any push", function()
		mem.setup({ backend = mock_backend })
		local r = mem.state()
		assert.is_nil(r)
	end)

	it("subscriber is called on first push", function()
		mem.setup({ backend = mock_backend })
		local r
		mem:subscribe(function(s)
			r = s
		end)
		push(state(4000))
		assert.equals(4000, r.used)
	end)

	it("stop() resets state and allows re-setup", function()
		mem.setup({ backend = mock_backend })
		push(state(4000))
		mem.stop()
		local r = mem.state()
		assert.is_nil(r)
		local new_cb
		mem.setup({ backend = {
			start = function(_self, cb)
				new_cb = cb
			end,
			stop = function() end,
		} })
		local r2
		mem:subscribe(function(s)
			r2 = s
		end)
		new_cb(state(8000))
		assert.equals(8000, r2.used)
	end)

	it("second setup() logs a warning and is a no-op", function()
		local warned = false
		require("gears").debug.print_warning = function()
			warned = true
		end
		mem.setup({ backend = mock_backend })
		mem.setup({ backend = mock_backend })
		assert.is_true(warned)
	end)

	it("subscribe replays current state immediately if available", function()
		mem.setup({ backend = mock_backend })
		push(state(4000))
		local replayed
		mem:subscribe(function(s)
			replayed = s
		end)
		assert.equals(4000, replayed.used)
	end)

	it("subscribe returns a callable unsubscribe function", function()
		mem.setup({ backend = mock_backend })
		local unsub = mem:subscribe(function() end)
		assert.is_function(unsub)
		unsub()
	end)

	it("state delivers state after a backend push", function()
		mem.setup({ backend = mock_backend })
		push(state(4000))
		local r = mem.state()
		assert.equals(4000, r.used)
	end)

	it("unsubscribe stops delivery", function()
		mem.setup({ backend = mock_backend })
		local calls = 0
		local unsub = mem:subscribe(function()
			calls = calls + 1
		end)
		push(state(4000))
		unsub()
		push(state(5000))
		assert.equals(1, calls)
	end)
end)
