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

	describe("map", function()
		it("returns a new Subscribable", function()
			local inst = Subscribable({})
			local mapped = inst:map(function(s)
				return s
			end)
			assert.not_equals(inst, mapped)
			assert.is_function(mapped.subscribe)
		end)

		it("initial state is nil when source has no state", function()
			local inst = Subscribable({})
			local mapped = inst:map(function(s)
				return s * 2
			end)
			assert.is_nil(mapped.state)
		end)

		it("initial state is mapped source state when source has state", function()
			local inst = Subscribable({ state = 5 })
			local mapped = inst:map(function(s)
				return s * 2
			end)
			assert.equals(10, mapped.state)
		end)

		it("maps a falsy initial state correctly", function()
			local inst = Subscribable({ state = false })
			local mapped = inst:map(function(s)
				return s == false and "was-false" or "other"
			end)
			assert.equals("was-false", mapped.state)
		end)

		it("propagates mapped value to subscribers on source push", function()
			local inst = Subscribable({})
			local mapped = inst:map(function(s)
				return s .. "!"
			end)
			local received
			mapped:subscribe(function(s)
				received = s
			end)
			inst:push("hello")
			assert.equals("hello!", received)
		end)

		it("updates mapped state on source push", function()
			local inst = Subscribable({})
			local mapped = inst:map(function(s)
				return s * 10
			end)
			inst:push(3)
			assert.equals(30, mapped.state)
		end)

		it("chained maps compose correctly", function()
			local inst = Subscribable({})
			local received
			inst:map(function(s)
				return s + 1
			end)
				:map(function(s)
					return s * 2
				end)
				:subscribe(function(s)
					received = s
				end)
			inst:push(4)
			assert.equals(10, received)
		end)
	end)

	describe("init", function()
		it("sets _subs to empty table", function()
			local inst = {}
			Subscribable.init(inst)
			assert.same({}, inst._subs)
		end)

		it("reset clears existing subscribers", function()
			local inst = Subscribable({})
			inst:subscribe(function() end)
			assert.equals(1, #inst._subs)
			Subscribable.init(inst)
			assert.equals(0, #inst._subs)
		end)
	end)
end)
