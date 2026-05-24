---@class CombinableClass<T>
---@field MT        { __index: table }
---@field methods   table
---@field init      fun(inst?: table): table
---@field new       fun(inst?: table): T
---@overload        fun(inst?: table): T

--- Combines class extensions into a single class with merged MT and chained init.
--- Asserts at call time that no method key is defined by more than one extension.
---@param ... CombinableClass Classes with `.MT.__index` and `.init` fields
---@return CombinableClass
local function extend(...)
	local classes = { ... }
	local result = {}
	result.MT = { __index = {} }
	for _, class in ipairs(classes) do
		for k, v in pairs(class.MT.__index) do
			assert(not result.MT.__index[k], "Class extension key conflict: " .. tostring(k))
			result.MT.__index[k] = v
		end
	end
	result.methods = result.MT.__index
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

return extend
