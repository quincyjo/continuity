-- spec/sysinfo_net_spec.lua
require("spec.support.awesome_mocks")

describe("sysinfo.net module", function()
	local net, captured_cb, mock_backend

	before_each(function()
		package.loaded["continuity.sysinfo.net"] = nil
		captured_cb = nil
		mock_backend = {
			start = function(_self, cb)
				captured_cb = cb
			end,
			stop = function(_self) end,
		}
		net = require("continuity.sysinfo.net")
	end)

	local function push(s)
		captured_cb(s)
	end

	local function state(tx, rx)
		return {
			tx_rate = tx,
			rx_rate = rx,
			devices = {
				eth0 = {
					state = "up",
					carrier = true,
					tx_rate = tx,
					rx_rate = rx,
					tx_bytes = 100000,
					rx_bytes = 200000,
					wifi = false,
					signal = nil,
				},
			},
		}
	end

	it("state delivers nil before any push", function()
		net.setup({ backend = mock_backend })
		local r = net.state
		assert.is_nil(r)
	end)

	it("subscriber called on push", function()
		net.setup({ backend = mock_backend })
		local r
		net:subscribe(function(s)
			r = s
		end)
		push(state(1024, 2048))
		assert.equals(1024, r.tx_rate)
	end)

	it("subscriber called when tx_rate changes", function()
		net.setup({ backend = mock_backend })
		local calls = 0
		net:subscribe(function()
			calls = calls + 1
		end)
		push(state(0, 0))
		push(state(1024, 0))
		assert.equals(2, calls)
	end)

	it("subscriber called when device link state changes", function()
		net.setup({ backend = mock_backend })
		local calls = 0
		net:subscribe(function()
			calls = calls + 1
		end)
		push(state(0, 0))
		local s2 = state(0, 0)
		s2.devices.eth0.state = "down"
		push(s2)
		assert.equals(2, calls)
	end)

	it("stop() resets and allows re-setup", function()
		net.setup({ backend = mock_backend })
		push(state(100, 200))
		net.stop()
		local r = net.state
		assert.is_nil(r)
		local new_cb
		net.setup({ backend = {
			start = function(_, cb)
				new_cb = cb
			end,
			stop = function() end,
		} })
		local r2
		net:subscribe(function(s)
			r2 = s
		end)
		new_cb(state(500, 1000))
		assert.equals(500, r2.tx_rate)
	end)

	it("subscribe replays current state immediately if available", function()
		net.setup({ backend = mock_backend })
		push(state(1000, 2000))
		local replayed
		net:subscribe(function(s)
			replayed = s
		end)
		assert.equals(1000, replayed.tx_rate)
	end)

	it("subscribe returns a callable unsubscribe function", function()
		net.setup({ backend = mock_backend })
		local unsub = net:subscribe(function() end)
		assert.is_function(unsub)
		unsub()
	end)

	it("state delivers state after a backend push", function()
		net.setup({ backend = mock_backend })
		push(state(1024, 2048))
		local r = net.state
		assert.equals(1024, r.tx_rate)
	end)

	it("unsubscribe stops delivery", function()
		net.setup({ backend = mock_backend })
		local calls = 0
		local unsub = net:subscribe(function()
			calls = calls + 1
		end)
		push(state(0, 0))
		unsub()
		push(state(1024, 0))
		assert.equals(1, calls)
	end)

	it("second setup() logs a warning and is a no-op", function()
		local warned = false
		require("gears").debug.print_warning = function()
			warned = true
		end
		net.setup({ backend = mock_backend })
		net.setup({ backend = mock_backend })
		assert.is_true(warned)
	end)

	it("unsubscribing one subscriber does not affect other subscribers", function()
		net.setup({ backend = mock_backend })
		local calls1, calls2 = 0, 0
		local fn1 = function()
			calls1 = calls1 + 1
		end
		local fn2 = function()
			calls2 = calls2 + 1
		end
		local unsub1 = net:subscribe(fn1)
		net:subscribe(fn2)
		unsub1()
		push(state(1024, 2048))
		assert.equals(0, calls1)
		assert.equals(1, calls2)
	end)
end)
