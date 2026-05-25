require("spec.support.awesome_mocks")
local Monitor = require("continuity.monitor")

local function make()
	return Monitor({})
end

describe("Monitor", function()
	it("state is nil before first push", function()
		local m = make()
		assert.is_nil(m.state)
	end)

	it("push sets state", function()
		local m = make()
		m:push({ value = 1 })
		assert.equals(1, m.state.value)
	end)

	it("subscribe replays current state immediately if state is set", function()
		local m = make()
		m:push({ value = 1 })
		local received = {}
		m:subscribe(function(s)
			received[#received + 1] = s
		end)
		assert.equals(1, #received)
		assert.equals(1, received[1].value)
	end)

	it("subscribe does not fire if state is nil", function()
		local m = make()
		local fired = false
		m:subscribe(function()
			fired = true
		end)
		assert.is_false(fired)
	end)

	it("push notifies all subscribers", function()
		local m = make()
		local a, b = {}, {}
		m:subscribe(function(s)
			a[#a + 1] = s
		end)
		m:subscribe(function(s)
			b[#b + 1] = s
		end)
		m:push({ value = 2 })
		assert.equals(1, #a)
		assert.equals(1, #b)
		assert.equals(2, a[1].value)
	end)

	it("subscribe returns an unsubscribe function that stops future notifications", function()
		local m = make()
		local received = {}
		local unsub = m:subscribe(function(s)
			received[#received + 1] = s
		end)
		unsub()
		m:push({ value = 3 })
		assert.equals(0, #received)
	end)

	it("unsubscribe does not affect other subscribers", function()
		local m = make()
		local a, b = {}, {}
		local unsub = m:subscribe(function(s)
			a[#a + 1] = s
		end)
		m:subscribe(function(s)
			b[#b + 1] = s
		end)
		unsub()
		m:push({ value = 4 })
		assert.equals(0, #a)
		assert.equals(1, #b)
	end)
end)
