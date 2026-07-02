require("spec.support.awesome_mocks")

local Removable = require("continuity.class.removable")

describe("Removable", function()
	describe("on_removed", function()
		it("calls callback when fired", function()
			local inst = Removable({})
			local received
			inst:on_removed(function(id)
				received = id
			end)
			inst:remove_event("dev-1")
			assert.equals("dev-1", received)
		end)

		it("calls multiple callbacks", function()
			local inst = Removable({})
			local a, b
			inst:on_removed(function(id)
				a = id
			end)
			inst:on_removed(function(id)
				b = id
			end)
			inst:remove_event("dev-1")
			assert.equals("dev-1", a)
			assert.equals("dev-1", b)
		end)

		it("returns an unsubscribe function that stops callbacks", function()
			local inst = Removable({})
			local count = 0
			local unsub = inst:on_removed(function()
				count = count + 1
			end)
			unsub()
			inst:remove_event("dev-1")
			assert.equals(0, count)
		end)
	end)

	describe("init", function()
		it("reset clears existing callbacks", function()
			local inst = Removable({})
			local count = 0
			inst:on_removed(function()
				count = count + 1
			end)
			Removable.init(inst)
			inst:remove_event("dev-1")
			assert.equals(0, count)
		end)
	end)

	describe("remove_event", function()
		it("fires _removed_cbs with the id", function()
			local inst = Removable({})
			local received
			inst:on_removed(function(id)
				received = id
			end)
			inst:remove_event("dev-1")
			assert.equals("dev-1", received)
		end)

		it("fires weak callbacks with the id via remove_event", function()
			local inst = Removable({})
			local received
			local cb = function(id)
				received = id
			end
			inst:weak_on_removed(cb)
			inst:remove_event("dev-1")
			assert.equals("dev-1", received)
		end)

		it("fires both strong and weak callbacks", function()
			local inst = Removable({})
			local order = {}
			inst:on_removed(function()
				order[#order + 1] = "strong"
			end)
			local cb = function()
				order[#order + 1] = "weak"
			end
			inst:weak_on_removed(cb)
			inst:remove_event("dev-1")
			assert.equals(2, #order)
		end)

		it("resets subscription tables after firing", function()
			local inst = Removable({})
			local count = 0
			inst:on_removed(function()
				count = count + 1
			end)
			inst:remove_event("dev-1")
			inst:remove_event("dev-1")
			assert.equals(1, count)
		end)
	end)

	describe("weak_on_removed", function()
		it("calls callback when fired while the callback is held", function()
			local inst = Removable({})
			local received
			local cb = function(id)
				received = id
			end
			inst:weak_on_removed(cb)
			inst:remove_event("dev-1")
			assert.equals("dev-1", received)
		end)

		it("returns an unsubscribe function that stops callbacks", function()
			local inst = Removable({})
			local count = 0
			local cb = function()
				count = count + 1
			end
			local unsub = inst:weak_on_removed(cb)
			unsub()
			inst:remove_event("dev-1")
			assert.equals(0, count)
		end)

		it("does not fire after the callback reference is released and GC is forced", function()
			local inst = Removable({})
			local fired = false
			local cb = function()
				fired = true
			end
			inst:weak_on_removed(cb)
			cb = nil -- luacheck: ignore
			collectgarbage("collect")
			inst:remove_event("dev-1")
			assert.is_false(fired)
		end)
	end)
end)
