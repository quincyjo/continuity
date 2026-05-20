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
			for _, cb in ipairs(inst._removed_cbs) do
				cb("dev-1")
			end
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
			for _, cb in ipairs(inst._removed_cbs) do
				cb("dev-1")
			end
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
			for _, cb in ipairs(inst._removed_cbs) do
				cb("dev-1")
			end
			assert.equals(0, count)
		end)
	end)

	describe("init", function()
		it("sets _removed_cbs to empty table", function()
			local inst = {}
			Removable.init(inst)
			assert.same({}, inst._removed_cbs)
		end)

		it("reset clears existing callbacks", function()
			local inst = Removable({})
			inst:on_removed(function() end)
			assert.equals(1, #inst._removed_cbs)
			Removable.init(inst)
			assert.equals(0, #inst._removed_cbs)
		end)
	end)
end)
