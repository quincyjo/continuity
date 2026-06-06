require("spec.support.awesome_mocks")

local WeakSubscriptions = require("continuity.util.weak_subscriptions")

describe("WeakSubscriptions", function()
	it("add returns an integer id", function()
		local subs = WeakSubscriptions()
		local id = subs:add(function() end)
		assert.is_number(id)
	end)

	it("add returns incrementing ids", function()
		local subs = WeakSubscriptions()
		local id1 = subs:add(function() end)
		local id2 = subs:add(function() end)
		assert.not_equals(id1, id2)
	end)

	it("fire calls all live callbacks with the given arguments", function()
		local subs = WeakSubscriptions()
		local calls = {}
		local cb_a = function(v)
			calls[#calls + 1] = "a:" .. v
		end
		local cb_b = function(v)
			calls[#calls + 1] = "b:" .. v
		end
		subs:add(cb_a)
		subs:add(cb_b)
		subs:fire("x")
		assert.equals(2, #calls)
		assert.is_true(calls[1] == "a:x" or calls[1] == "b:x")
		assert.is_true(calls[2] == "a:x" or calls[2] == "b:x")
		assert.not_equals(calls[1], calls[2])
	end)

	it("remove prevents the callback from firing", function()
		local subs = WeakSubscriptions()
		local count = 0
		local cb = function()
			count = count + 1
		end
		local id = subs:add(cb)
		subs:remove(id)
		subs:fire()
		assert.equals(0, count)
	end)

	it("remove is idempotent", function()
		local subs = WeakSubscriptions()
		local cb = function() end
		local id = subs:add(cb)
		subs:remove(id)
		assert.has_no.errors(function()
			subs:remove(id)
		end)
	end)

	it("fire is safe after remove (no error, remaining cbs fire)", function()
		local subs = WeakSubscriptions()
		local count = 0
		local cb_a = function()
			count = count + 1
		end
		local cb_b = function()
			count = count + 1
		end
		local id = subs:add(cb_a)
		subs:add(cb_b)
		subs:remove(id)
		assert.has_no.errors(function()
			subs:fire()
		end)
		assert.equals(1, count)
	end)

	it("iter yields all live callbacks", function()
		local subs = WeakSubscriptions()
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
		local subs = WeakSubscriptions()
		local received
		local cb = function(a, b, c)
			received = { a, b, c }
		end
		subs:add(cb)
		subs:fire(1, 2, 3)
		assert.same({ 1, 2, 3 }, received)
	end)

	-- GC test: weak values are collected when the only strong reference is dropped.
	-- collectgarbage("collect") is synchronous in Lua 5.3 and LuaJIT (single-threaded);
	-- the spec does not guarantee immediate collection in all implementations.
	it("does not fire a callback after its only strong reference is released and GC is forced", function()
		local subs = WeakSubscriptions()
		local fired = false
		local cb = function()
			fired = true
		end
		subs:add(cb)
		cb = nil -- luacheck: ignore
		collectgarbage("collect")
		subs:fire()
		assert.is_false(fired)
	end)

	it("a live callback fires alongside a collected callback", function()
		local subs = WeakSubscriptions()
		local weak_fired = false
		local strong_fired = false
		local weak_cb = function()
			weak_fired = true
		end
		local strong_cb = function()
			strong_fired = true
		end
		subs:add(weak_cb)
		subs:add(strong_cb)
		weak_cb = nil -- luacheck: ignore
		collectgarbage("collect")
		subs:fire()
		assert.is_false(weak_fired)
		assert.is_true(strong_fired)
	end)
end)
