---@class CombinableClass<T>
---@field MT        { __index: table }
---@field methods   table
---@field init      fun(inst: table): table
---@field new       fun(inst: table): T
---@overload        fun(inst: table): T

---@class Extend
---@overload fun(...: { init: fun(inst: table), methods: table<string, function>}): CombinableClass
local Extend = {}

---@param classes { init: fun(inst: table), methods: table<string, function>}[]
---@param allow_overrides boolean
---@return CombinableClass
local function merge(classes, allow_overrides)
	local result = {}
	result.methods = {}
	for _, class in ipairs(classes) do
		for k, v in pairs(class.methods) do
			if not allow_overrides then
				assert(not result.methods[k], "Class extension key conflict: " .. tostring(k))
			end
			result.methods[k] = v
		end
	end
	result.MT = { __index = result.methods }
	function result.init(inst)
		inst = inst or {}
		for _, class in ipairs(classes) do
			class.init(inst)
		end
		return inst
	end
	function result.new(inst)
		return setmetatable(result.init(inst), result.MT)
	end
	return setmetatable(result, {
		__call = function(self, inst)
			return self.new(inst)
		end,
	})
end

---@param class { methods: table, init: fun(inst: table): table }
---@return CombinableClass
function Extend.new(class)
	local MT = { __index = class.methods }
	return setmetatable({
		MT = MT,
		methods = class.methods,
		init = class.init,
		new = function(inst)
			return setmetatable(class.init(inst), MT)
		end,
	}, {
		__call = function(self, inst)
			return self.new(inst)
		end,
	})
end

--- Combines class extensions into a single class with merged MT and chained init.
--- Asserts at call time that no method key is defined by more than one extension.
---@param ... { init: fun(inst: table), methods: table<string, function>}[]
---@return CombinableClass
function Extend.combine(...)
	return merge({ ... }, false)
end

--- Combines class extensions into a single class with merged MT and chained init.
--- Allows overrides of existing methods, with the last class taking precedence.
---@param ... { init: fun(inst: table), methods: table<string, function>}[]
---@return CombinableClass
function Extend.override(...)
	return merge({ ... }, true)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Extend, {
	__call = function(self, ...)
		return self.combine(...)
	end,
})

return Extend
