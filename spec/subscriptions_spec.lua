require("spec.support.awesome_mocks")

local Subscriptions = require("continuity.util.subscriptions")

describe("Subscriptions", function()
	it("add returns an integer id", function()
		local subs = Subscriptions()
		local id = subs:add(function() end)
		assert.is_number(id)
	end)

	it("add returns incrementing ids", function()
		local subs = Subscriptions()
		local id1 = subs:add(function() end)
		local id2 = subs:add(function() end)
		assert.not_equals(id1, id2)
	end)

	it("fire calls all callbacks with the given arguments", function()
		local subs = Subscriptions()
		local calls = {}
		subs:add(function(v)
			calls[#calls + 1] = "a:" .. v
		end)
		subs:add(function(v)
			calls[#calls + 1] = "b:" .. v
		end)
		subs:fire("x")
		assert.equals(2, #calls)
		assert.is_true(calls[1] == "a:x" or calls[1] == "b:x")
		assert.is_true(calls[2] == "a:x" or calls[2] == "b:x")
		assert.not_equals(calls[1], calls[2])
	end)

	it("remove prevents the callback from firing", function()
		local subs = Subscriptions()
		local count = 0
		local id = subs:add(function()
			count = count + 1
		end)
		subs:remove(id)
		subs:fire()
		assert.equals(0, count)
	end)

	it("remove is idempotent", function()
		local subs = Subscriptions()
		local id = subs:add(function() end)
		subs:remove(id)
		assert.has_no.errors(function()
			subs:remove(id)
		end)
	end)

	it("fire is safe after remove (no error, remaining cbs fire)", function()
		local subs = Subscriptions()
		local count = 0
		local id = subs:add(function()
			count = count + 1
		end)
		subs:add(function()
			count = count + 1
		end)
		subs:remove(id)
		assert.has_no.errors(function()
			subs:fire()
		end)
		assert.equals(1, count)
	end)

	it("iter yields all live callbacks", function()
		local subs = Subscriptions()
		local a, b = function() end, function() end
		local id_a = subs:add(a)
		subs:add(b)
		subs:remove(id_a)
		local found = {}
		for _, cb in subs:iter() do
			found[#found + 1] = cb
		end
		assert.equals(1, #found)
		assert.equals(b, found[1])
	end)

	it("fire with multiple arguments passes all to each callback", function()
		local subs = Subscriptions()
		local received
		subs:add(function(a, b, c)
			received = { a, b, c }
		end)
		subs:fire(1, 2, 3)
		assert.same({ 1, 2, 3 }, received)
	end)
end)
