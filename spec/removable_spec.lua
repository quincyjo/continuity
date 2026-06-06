require("spec.support.awesome_mocks")

local Removable = require("continuity.removable")

describe("Removable", function()
	describe("on_removed", function()
		it("calls callback when fired", function()
			local inst = Removable({})
			local received
			inst:on_removed(function(id)
				received = id
			end)
			inst._removed_cbs:fire("dev-1")
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
			inst._removed_cbs:fire("dev-1")
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
			inst._removed_cbs:fire("dev-1")
			assert.equals(0, count)
		end)
	end)

	describe("init", function()
		it("sets _removed_cbs to empty subscriptions", function()
			local inst = {}
			Removable.init(inst)
			local count = 0
			inst._removed_cbs:fire()
			assert.equals(0, count)
		end)

		it("reset clears existing callbacks", function()
			local inst = Removable({})
			local count = 0
			inst:on_removed(function()
				count = count + 1
			end)
			Removable.init(inst)
			inst._removed_cbs:fire("dev-1")
			assert.equals(0, count)
		end)
	end)
end)
