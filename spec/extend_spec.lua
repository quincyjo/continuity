require("spec.support.awesome_mocks")

local extend = require("continuity.util.extend")

describe("extend", function()
	local ClassA, ClassB

	before_each(function()
		ClassA = {
			MT = { __index = {} },
		}
		ClassA.methods = ClassA.MT.__index
		ClassA.MT.__index.foo = function(self)
			return self._a
		end
		function ClassA.init(inst)
			inst = inst or {}
			inst._a = "a"
			return inst
		end

		ClassB = {
			MT = { __index = {} },
		}
		ClassB.methods = ClassB.MT.__index
		ClassB.MT.__index.bar = function(self)
			return self._b
		end
		function ClassB.init(inst)
			inst = inst or {}
			inst._b = "b"
			return inst
		end
	end)

	it("merges methods from all classes", function()
		local Combined = extend(ClassA, ClassB)
		assert.is_not_nil(Combined.MT.__index.foo)
		assert.is_not_nil(Combined.MT.__index.bar)
		assert.equals(Combined.methods, Combined.MT.__index)
	end)

	it("init chains all class inits", function()
		local Combined = extend(ClassA, ClassB)
		local inst = Combined.init({})
		assert.equals("a", inst._a)
		assert.equals("b", inst._b)
	end)

	it("init works with no argument", function()
		local Combined = extend(ClassA, ClassB)
		local inst = Combined.init()
		assert.equals("a", inst._a)
		assert.equals("b", inst._b)
	end)

	it("methods are callable via setmetatable", function()
		local Combined = extend(ClassA, ClassB)
		local inst = setmetatable(Combined.init({}), Combined.MT)
		assert.equals("a", inst:foo())
		assert.equals("b", inst:bar())
	end)

	it("asserts on key conflict", function()
		ClassB.MT.__index.foo = function() end
		assert.has_error(function()
			extend(ClassA, ClassB)
		end, "Class extension key conflict: foo")
	end)

	it("init resets existing fields when called on existing instance", function()
		local Combined = extend(ClassA, ClassB)
		local inst = Combined.init({})
		inst._a = "modified"
		Combined.init(inst)
		assert.equals("a", inst._a)
	end)
end)
