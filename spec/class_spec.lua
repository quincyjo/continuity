require("spec.support.awesome_mocks")

local class = require("continuity.class")

describe("class", function()
	local ClassA, ClassB

	before_each(function()
		ClassA = class.new({
			methods = {
				foo = function(self)
					return self._a
				end,
			},
		})(function(inst)
			inst._a = "a"
		end)

		ClassB = class.new({
			methods = {
				bar = function(self)
					return self._b
				end,
			},
		})(function(inst)
			inst._b = "b"
		end)
	end)

	describe("class.union", function()
		it("merges methods from all classes", function()
			local Combined = class.union(ClassA, ClassB)
			local inst = Combined.new()
			assert.equals("a", inst:foo())
			assert.equals("b", inst:bar())
		end)

		it("chains all inits", function()
			local Combined = class.union(ClassA, ClassB)
			local inst = Combined.init({})
			assert.equals("a", inst._a)
			assert.equals("b", inst._b)
		end)

		it("init works with no argument", function()
			local Combined = class.union(ClassA, ClassB)
			local inst = Combined.init()
			assert.equals("a", inst._a)
			assert.equals("b", inst._b)
		end)

		it("instances are callable via __call", function()
			local Combined = class.union(ClassA, ClassB)
			local inst = Combined()
			assert.equals("a", inst:foo())
			assert.equals("b", inst:bar())
		end)

		it("asserts on key conflict", function()
			local ClassC = class.new({
				methods = { foo = function() end },
			})(function() end)
			assert.has_error(function()
				class.union(ClassA, ClassC)
			end, "class.union conflict: foo")
		end)

		it("init resets fields when called on existing instance", function()
			local Combined = class.union(ClassA, ClassB)
			local inst = Combined.init({})
			inst._a = "modified"
			Combined.init(inst)
			assert.equals("a", inst._a)
		end)
	end)

	describe("class.new builder", function()
		it(":extends copies base methods for missing keys", function()
			local Extended = class
				.new({
					methods = {
						baz = function()
							return "baz"
						end,
					},
				})
				:extends(ClassA)(function(inst)
				inst._extra = "extra"
			end)
			local inst = Extended.new()
			assert.equals("a", inst:foo())
			assert.equals("baz", inst:baz())
			assert.equals("a", inst._a)
			assert.equals("extra", inst._extra)
		end)

		it(":extends allows subclass to override super method", function()
			local Override = class
				.new({
					methods = {
						foo = function()
							return "overridden"
						end,
					},
				})
				:extends(ClassA)()
			local inst = Override.new()
			assert.equals("overridden", inst:foo())
		end)

		it(":extends chains inits — base runs first", function()
			local order = {}
			local Base = class.new({
				methods = {},
			})(function()
				order[#order + 1] = "base"
			end)
			local Sub = class
				.new({
					methods = {},
				})
				:extends(Base)(function()
				order[#order + 1] = "sub"
			end)
			Sub.new()
			assert.same({ "base", "sub" }, order)
		end)

		it(":with asserts on key conflict", function()
			assert.has_error(function()
				class
					.new({
						methods = { foo = function() end },
					})
					:with(ClassA)
			end, "class extension conflict: foo")
		end)

		it(":with chains inits", function()
			local Combined = class.new({}):with(ClassA):with(ClassB)()
			local inst = Combined.init()
			assert.equals("a", inst._a)
			assert.equals("b", inst._b)
		end)

		it("getters are dispatched via __index", function()
			local G = class.new({
				getters = {
					double = function(self)
						return self._val * 2
					end,
				},
			})(function(inst)
				inst._val = 5
			end)
			local inst = G.new()
			assert.equals(10, inst.double)
		end)

		it("finalized with no init_fn uses base init chain only", function()
			local Combined = class.new({}):with(ClassA)()
			local inst = Combined.new()
			assert.equals("a", inst._a)
		end)
	end)
end)
