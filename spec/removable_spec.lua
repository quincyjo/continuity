require("spec.support.awesome_mocks")

local Removable = require("continuity.class.removable")

describe("Removable", function()
	describe("on_removed", function()
		it("calls callback when fired", function()
			local inst = Removable({ id = "dev-1" })
			local received
			inst:on_removed(function(id)
				received = id
			end)
			Removable.teardown(inst)
			assert.equals("dev-1", received)
		end)

		it("calls multiple callbacks", function()
			local inst = Removable({ id = "dev-1" })
			local a, b
			inst:on_removed(function(id)
				a = id
			end)
			inst:on_removed(function(id)
				b = id
			end)
			Removable.teardown(inst)
			assert.equals("dev-1", a)
			assert.equals("dev-1", b)
		end)

		it("returns an unsubscribe function that stops callbacks", function()
			local inst = Removable({ id = "dev-1" })
			local count = 0
			local unsub = inst:on_removed(function()
				count = count + 1
			end)
			unsub()
			Removable.teardown(inst)
			assert.equals(0, count)
		end)
	end)

	describe("init", function()
		it("reset clears existing callbacks", function()
			local inst = Removable({ id = "dev-1" })
			local count = 0
			inst:on_removed(function()
				count = count + 1
			end)
			Removable.init(inst)
			Removable.teardown(inst)
			assert.equals(0, count)
		end)
	end)

	describe("teardown", function()
		it("fires _removed_cbs with the instance's own id", function()
			local inst = Removable({ id = "dev-1" })
			local received
			inst:on_removed(function(id)
				received = id
			end)
			Removable.teardown(inst)
			assert.equals("dev-1", received)
		end)

		it("fires weak callbacks with the id", function()
			local inst = Removable({ id = "dev-1" })
			local received
			local cb = function(id)
				received = id
			end
			inst:weak_on_removed(cb)
			Removable.teardown(inst)
			assert.equals("dev-1", received)
		end)

		it("fires both strong and weak callbacks", function()
			local inst = Removable({ id = "dev-1" })
			local order = {}
			inst:on_removed(function()
				order[#order + 1] = "strong"
			end)
			local cb = function()
				order[#order + 1] = "weak"
			end
			inst:weak_on_removed(cb)
			Removable.teardown(inst)
			assert.equals(2, #order)
		end)

		it("leaves the subscription table empty afterward", function()
			local inst = Removable({ id = "dev-1" })
			local count = 0
			inst:on_removed(function()
				count = count + 1
			end)
			Removable.teardown(inst)
			inst._removed_cbs:fire("dev-1")
			assert.equals(1, count)
		end)

		it("does not error when the instance has no id", function()
			local inst = Removable({})
			assert.has_no.errors(function()
				Removable.teardown(inst)
			end)
		end)
	end)

	describe("weak_on_removed", function()
		it("calls callback when fired while the callback is held", function()
			local inst = Removable({ id = "dev-1" })
			local received
			local cb = function(id)
				received = id
			end
			inst:weak_on_removed(cb)
			Removable.teardown(inst)
			assert.equals("dev-1", received)
		end)

		it("returns an unsubscribe function that stops callbacks", function()
			local inst = Removable({ id = "dev-1" })
			local count = 0
			local cb = function()
				count = count + 1
			end
			local unsub = inst:weak_on_removed(cb)
			unsub()
			Removable.teardown(inst)
			assert.equals(0, count)
		end)

		it("does not fire after the callback reference is released and GC is forced", function()
			local inst = Removable({ id = "dev-1" })
			local fired = false
			local cb = function()
				fired = true
			end
			inst:weak_on_removed(cb)
			cb = nil -- luacheck: ignore
			collectgarbage("collect")
			Removable.teardown(inst)
			assert.is_false(fired)
		end)
	end)
end)
