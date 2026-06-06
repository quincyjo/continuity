require("spec.support.awesome_mocks")

local Subscribable = require("continuity.subscribable")

describe("Subscribable", function()
	describe("subscribe", function()
		it("calls callback when push is called", function()
			local inst = Subscribable({})
			local received
			inst:subscribe(function(s)
				received = s
			end)
			inst:push("hello")
			assert.equals("hello", received)
		end)

		it("calls multiple subscribers", function()
			local inst = Subscribable({})
			local a, b
			inst:subscribe(function(s)
				a = s
			end)
			inst:subscribe(function(s)
				b = s
			end)
			inst:push(42)
			assert.equals(42, a)
			assert.equals(42, b)
		end)

		it("returns an unsubscribe function that stops callbacks", function()
			local inst = Subscribable({})
			local count = 0
			local unsub = inst:subscribe(function()
				count = count + 1
			end)
			inst:push(1)
			unsub()
			inst:push(2)
			assert.equals(1, count)
		end)

		it("does not replay state on new subscribe", function()
			local inst = Subscribable({})
			inst:push("existing")
			local called = false
			inst:subscribe(function()
				called = true
			end)
			assert.is_false(called)
		end)
	end)

	describe("push", function()
		it("sets self.state", function()
			local inst = Subscribable({})
			inst:push({ level = 50 })
			assert.equals(50, inst.state.level)
		end)

		it("fans out to all subscribers with new state", function()
			local inst = Subscribable({})
			local got = {}
			inst:subscribe(function(s)
				got[#got + 1] = s
			end)
			inst:subscribe(function(s)
				got[#got + 1] = s
			end)
			inst:push("x")
			assert.equals(2, #got)
		end)
	end)

	describe("init", function()
		it("sets _subs to empty subscriptions", function()
			local inst = {}
			Subscribable.init(inst)
			local count = 0
			inst._subs:fire()
			assert.equals(0, count)
		end)

		it("reset clears existing subscribers", function()
			local inst = Subscribable({})
			local count = 0
			inst:subscribe(function()
				count = count + 1
			end)
			Subscribable.init(inst)
			inst:push("x")
			assert.equals(0, count)
		end)
	end)

	describe("weak_subscribe", function()
		it("calls the callback on push while the callback is held", function()
			local inst = Subscribable({})
			local received
			local cb = function(s)
				received = s
			end
			inst:weak_subscribe(cb)
			inst:push("hello")
			assert.equals("hello", received)
		end)

		it("returns an unsubscribe function that stops callbacks", function()
			local inst = Subscribable({})
			local count = 0
			local cb = function()
				count = count + 1
			end
			local unsub = inst:weak_subscribe(cb)
			inst:push(1)
			unsub()
			inst:push(2)
			assert.equals(1, count)
		end)

		it("does not fire after the callback reference is released and GC is forced", function()
			local inst = Subscribable({})
			local fired = false
			local cb = function()
				fired = true
			end
			inst:weak_subscribe(cb)
			cb = nil -- luacheck: ignore
			collectgarbage("collect")
			inst:push("x")
			assert.is_false(fired)
		end)

		it("strong and weak subscribers coexist; dropping weak does not affect strong", function()
			local inst = Subscribable({})
			local strong_count = 0
			local weak_fired = false
			inst:subscribe(function()
				strong_count = strong_count + 1
			end)
			local weak_cb = function()
				weak_fired = true
			end
			inst:weak_subscribe(weak_cb)
			weak_cb = nil -- luacheck: ignore
			collectgarbage("collect")
			inst:push("x")
			assert.equals(1, strong_count)
			assert.is_false(weak_fired)
		end)
	end)
end)
