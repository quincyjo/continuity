require("spec.support.awesome_mocks")

local gears = require("gears")
local DebouncedSubscriptions = require("continuity.util.subscriptions.debounced")

describe("DebouncedSubscriptions", function()
	local debounced
	local when_empty_calls

	before_each(function()
		gears._created = {}
		when_empty_calls = 0
		debounced = DebouncedSubscriptions(0.3, function()
			when_empty_calls = when_empty_calls + 1
		end)
	end)

	local function timer()
		return gears._created[1]
	end

	describe("add", function()
		it("returns an unsub function", function()
			local unsub = debounced:add(function() end)
			assert.is_function(unsub)
		end)

		it("fire does not call cb immediately", function()
			local called = false
			debounced:add(function()
				called = true
			end)
			debounced:fire("x")
			assert.is_false(called)
		end)

		it("fire calls timer:again", function()
			debounced:add(function() end)
			debounced:fire("x")
			assert.equals(1, timer().again_count)
		end)

		it("timer callback fires cb with the event args", function()
			local received
			debounced:add(function(v)
				received = v
			end)
			debounced:fire("hello")
			timer():fire()
			assert.equals("hello", received)
		end)

		it("timer callback fires cb with multiple event args", function()
			local received
			debounced:add(function(a, b)
				received = { a, b }
			end)
			debounced:fire(1, 2)
			timer():fire()
			assert.same({ 1, 2 }, received)
		end)

		it("cb receives args from the last fire when timer fires once", function()
			local received
			debounced:add(function(v)
				received = v
			end)
			debounced:fire("first")
			debounced:fire("last")
			timer():fire()
			assert.equals("last", received)
		end)

		it("unsub prevents cb from firing when timer fires", function()
			local called = false
			local unsub = debounced:add(function()
				called = true
			end)
			unsub()
			debounced:fire("x")
			timer():fire()
			assert.is_false(called)
		end)

		it("unsub is idempotent", function()
			local unsub = debounced:add(function() end)
			unsub()
			assert.has_no.errors(function()
				unsub()
			end)
		end)
	end)

	describe("weak_add", function()
		it("returns an unsub function", function()
			local cb = function() end
			local unsub = debounced:weak_add(cb)
			assert.is_function(unsub)
		end)

		it("timer callback fires cb while cb is strongly held", function()
			local called = false
			local cb = function()
				called = true
			end
			debounced:weak_add(cb)
			debounced:fire("x")
			timer():fire()
			assert.is_true(called)
			cb = nil -- luacheck: ignore
		end)

		it("does not fire cb after its only strong reference is GC'd", function()
			local called = false
			local cb = function()
				called = true
			end
			debounced:weak_add(cb)
			cb = nil -- luacheck: ignore
			collectgarbage("collect")
			debounced:fire("x")
			timer():fire()
			assert.is_false(called)
		end)
	end)

	describe("when_empty", function()
		it("is called when timer fires with no subscribers", function()
			debounced:fire("x")
			timer():fire()
			assert.equals(1, when_empty_calls)
		end)

		it("is not called when timer fires with a subscriber present", function()
			debounced:add(function() end)
			debounced:fire("x")
			timer():fire()
			assert.equals(0, when_empty_calls)
		end)

		it("is called after the last subscriber unsubscribes and timer fires", function()
			local unsub = debounced:add(function() end)
			unsub()
			debounced:fire("x")
			timer():fire()
			assert.equals(1, when_empty_calls)
		end)

		it("is not called when a weak cb is still alive", function()
			local cb = function() end
			debounced:weak_add(cb)
			debounced:fire("x")
			timer():fire()
			assert.equals(0, when_empty_calls)
			cb = nil -- luacheck: ignore
		end)
	end)
end)
