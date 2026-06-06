require("spec.support.awesome_mocks")

local Subscriptions = require("continuity.util.subscriptions")

describe("Subscriptions", function()
	describe("Strong", function()
		it("add returns an unsub function", function()
			local subs = Subscriptions()
			local unsub = subs:add(function() end)
			assert.is_function(unsub)
		end)

		it("add returns distincs unsubs", function()
			local subs = Subscriptions()
			local unsub1 = subs:add(function() end)
			local unsub2 = subs:add(function() end)
			assert.not_equals(unsub1, unsub2)
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
			local remove = subs:add(function()
				count = count + 1
			end)
			remove()
			subs:fire()
			assert.equals(0, count)
		end)

		it("remove is idempotent", function()
			local subs = Subscriptions()
			local remove = subs:add(function() end)
			remove()
			assert.has_no.errors(function()
				remove()
			end)
		end)

		it("fire is safe after remove (no error, remaining cbs fire)", function()
			local subs = Subscriptions()
			local count = 0
			local remove = subs:add(function()
				count = count + 1
			end)
			subs:add(function()
				count = count + 1
			end)
			remove()
			assert.has_no.errors(function()
				subs:fire()
			end)
			assert.equals(1, count)
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

	describe("weak_add", function()
		it("add returns an unsub function", function()
			local subs = Subscriptions()
			local unsub = subs:weak_add(function() end)
			assert.is_function(unsub)
		end)

		it("weak_add returns distinct unsub", function()
			local subs = Subscriptions()
			local unsub1 = subs:weak_add(function() end)
			local unsub2 = subs:weak_add(function() end)
			assert.not_equals(unsub1, unsub2)
		end)

		it("fire calls all live callbacks with the given arguments", function()
			local subs = Subscriptions()
			local calls = {}
			local cb_a = function(v)
				calls[#calls + 1] = "a:" .. v
			end
			local cb_b = function(v)
				calls[#calls + 1] = "b:" .. v
			end
			subs:weak_add(cb_a)
			subs:weak_add(cb_b)
			subs:fire("x")
			assert.equals(2, #calls)
			assert.is_true(calls[1] == "a:x" or calls[1] == "b:x")
			assert.is_true(calls[2] == "a:x" or calls[2] == "b:x")
			assert.not_equals(calls[1], calls[2])
		end)

		it("remove prevents the callback from firing", function()
			local subs = Subscriptions()
			local count = 0
			local cb = function()
				count = count + 1
			end
			local remove = subs:weak_add(cb)
			remove()
			subs:fire()
			assert.equals(0, count)
		end)

		it("remove is idempotent", function()
			local subs = Subscriptions()
			local cb = function() end
			local remove = subs:weak_add(cb)
			remove()
			assert.has_no.errors(function()
				remove()
			end)
		end)

		it("fire is safe after remove (no error, remaining cbs fire)", function()
			local subs = Subscriptions()
			local count = 0
			local cb_a = function()
				count = count + 1
			end
			local cb_b = function()
				count = count + 1
			end
			local remove = subs:weak_add(cb_a)
			subs:weak_add(cb_b)
			remove()
			assert.has_no.errors(function()
				subs:fire()
			end)
			assert.equals(1, count)
		end)

		it("fire with multiple arguments passes all to each callback", function()
			local subs = Subscriptions()
			local received
			local cb = function(a, b, c)
				received = { a, b, c }
			end
			subs:weak_add(cb)
			subs:fire(1, 2, 3)
			assert.same({ 1, 2, 3 }, received)
		end)

		-- GC test: weak_add values are collected when the only strong reference is dropped.
		-- collectgarbage("collect") is synchronous in Lua 5.3 and LuaJIT (single-threaded);
		-- the spec does not guarantee immediate collection in all implementations.
		it("does not fire a callback after its only strong reference is released and GC is forced", function()
			local subs = Subscriptions()
			local fired = false
			local cb = function()
				fired = true
			end
			subs:weak_add(cb)
			cb = nil -- luacheck: ignore
			collectgarbage("collect")
			subs:fire()
			assert.is_false(fired)
		end)

		it("a live callback fires alongside a collected callback", function()
			local subs = Subscriptions()
			local weak_add_fired = false
			local strong_fired = false
			local weak_add_cb = function()
				weak_add_fired = true
			end
			local strong_cb = function()
				strong_fired = true
			end
			subs:weak_add(weak_add_cb)
			subs:weak_add(strong_cb)
			weak_add_cb = nil -- luacheck: ignore
			collectgarbage("collect")
			subs:fire()
			assert.is_false(weak_add_fired)
			assert.is_true(strong_fired)
		end)

		it("subscription fires when only the unsub is held", function()
			local subs = Subscriptions()
			local fired = false
			local unsub -- luacheck: ignore
			do
				local cb = function()
					fired = true
				end
				unsub = subs:weak_add(cb)
			end
			collectgarbage("collect")
			subs:fire()
			assert.is_true(fired)

			unsub = nil -- luacheck: ignore
			collectgarbage("collect")
			fired = false
			subs:fire()
			assert.is_false(fired)
		end)
	end)

	describe("set semantics", function()
		it("add with the same cb twice fires the callback once", function()
			local subs = Subscriptions()
			local count = 0
			local cb = function()
				count = count + 1
			end
			subs:add(cb)
			subs:add(cb)
			subs:fire()
			assert.equals(1, count)
		end)

		it("weak_add with the same cb twice fires the callback once", function()
			local subs = Subscriptions()
			local count = 0
			local cb = function()
				count = count + 1
			end
			subs:weak_add(cb)
			subs:weak_add(cb)
			subs:fire()
			assert.equals(1, count)
		end)

		it("either unsub from duplicate add cancels the subscription", function()
			local subs = Subscriptions()
			local count = 0
			local cb = function()
				count = count + 1
			end
			local unsub_a = subs:add(cb)
			subs:add(cb)
			subs:fire()
			assert.equals(1, count)

			unsub_a()
			subs:fire()
			assert.equals(1, count)
		end)
	end)
end)
