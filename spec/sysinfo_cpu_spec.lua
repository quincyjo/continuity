-- spec/sysinfo_cpu_spec.lua
require("spec.support.awesome_mocks")

describe("sysinfo.cpu module", function()
	local cpu
	local captured_cb, mock_backend

	before_each(function()
		package.loaded["continuity.sysinfo.cpu"] = nil
		captured_cb = nil
		mock_backend = {
			start = function(self, cb)
				captured_cb = cb
			end,
			stop = function(self) end,
		}
		cpu = require("continuity.sysinfo.cpu")
	end)

	local function push(state)
		captured_cb(state)
	end

	local function state(usage)
		return { usage = usage, user = 0, system = 0, idle = 0, iowait = 0, steal = 0, cores = {} }
	end

	it("subscribe replays current state immediately if available", function()
		cpu.setup({ backend = mock_backend })
		captured_cb({ usage = 42, user = 10, system = 5, idle = 85, iowait = 0, steal = 0, cores = {} })
		local replayed
		cpu:subscribe(function(s)
			replayed = s
		end)
		assert.equals(42, replayed.usage)
	end)

	it("subscribe returns a callable unsubscribe function", function()
		cpu.setup({ backend = mock_backend })
		local unsub = cpu:subscribe(function() end)
		assert.is_function(unsub)
		unsub()
	end)

	it("state delivers nil before any backend push", function()
		cpu.setup({ backend = mock_backend })
		local result = "not_called"
		result = cpu.state()
		assert.is_nil(result)
	end)

	it("subscriber is called when backend pushes state", function()
		cpu.setup({ backend = mock_backend })
		local received
		cpu:subscribe(function(s)
			received = s
		end)
		push(state(50))
		assert.equals(50, received.usage)
	end)

	it("state delivers state after a backend push", function()
		cpu.setup({ backend = mock_backend })
		push(state(42))
		local result
		result = cpu.state()
		assert.equals(42, result.usage)
	end)

	it("subscriber IS called when state changes", function()
		cpu.setup({ backend = mock_backend })
		local calls = 0
		cpu:subscribe(function()
			calls = calls + 1
		end)
		push(state(50))
		push(state(60))
		assert.equals(2, calls)
	end)

	it("unsubscribe stops delivery", function()
		cpu.setup({ backend = mock_backend })
		local calls = 0
		local unsub = cpu:subscribe(function()
			calls = calls + 1
		end)
		push(state(50))
		unsub()
		push(state(60))
		assert.equals(1, calls)
	end)

	it("second setup() call logs a warning and is a no-op", function()
		local warned = false
		require("gears").debug.print_warning = function()
			warned = true
		end
		cpu.setup({ backend = mock_backend })
		local second_backend = { start = function() end, stop = function() end }
		cpu.setup({ backend = second_backend })
		assert.is_true(warned)
		-- original backend's cb is still active
		local received
		cpu:subscribe(function(s)
			received = s
		end)
		push(state(10))
		assert.equals(10, received.usage)
	end)

	it("stop() clears state, subscribers, and allows re-setup", function()
		cpu.setup({ backend = mock_backend })
		push(state(50))
		cpu.stop()
		local result = "not_called"
		result = cpu.state()
		assert.is_nil(result)
		-- re-setup works
		local new_cb
		local new_backend = {
			start = function(self, cb)
				new_cb = cb
			end,
			stop = function() end,
		}
		cpu.setup({ backend = new_backend })
		local received
		cpu:subscribe(function(s)
			received = s
		end)
		new_cb(state(99))
		assert.equals(99, received.usage)
	end)
end)
