local Controllable = require("continuity.controllable")

local function make()
	return Controllable({})
end

describe("Controllable", function()
	it("on_control registers a callback", function()
		local m = make()
		local received = {}
		m:on_control(function(s)
			received[#received + 1] = s
		end)
		m:control_event({ value = 1 })
		assert.equals(1, #received)
		assert.equals(1, received[1].value)
	end)

	it("control_event notifies all on_control subscribers", function()
		local m = make()
		local a, b = {}, {}
		m:on_control(function(s)
			a[#a + 1] = s
		end)
		m:on_control(function(s)
			b[#b + 1] = s
		end)
		m:control_event({ value = 2 })
		assert.equals(1, #a)
		assert.equals(1, #b)
	end)

	it("on_control returns an unsubscribe function", function()
		local m = make()
		local received = {}
		local unsub = m:on_control(function(s)
			received[#received + 1] = s
		end)
		unsub()
		m:control_event({ value = 3 })
		assert.equals(0, #received)
	end)

	it("unsubscribe does not affect other on_control subscribers", function()
		local m = make()
		local a, b = {}, {}
		local unsub = m:on_control(function(s)
			a[#a + 1] = s
		end)
		m:on_control(function(s)
			b[#b + 1] = s
		end)
		unsub()
		m:control_event({ value = 4 })
		assert.equals(0, #a)
		assert.equals(1, #b)
	end)

	it("does not replay past control events to new subscribers", function()
		local m = make()
		m:control_event({ value = 5 })
		local fired = false
		m:on_control(function()
			fired = true
		end)
		assert.is_false(fired)
	end)
end)
