---@class CombinedClass
---@field MT        { __index: table }
---@field methods   table
---@field init      fun(inst?: table): table

--- Combines class extensions into a single class with merged MT and chained init.
--- Asserts at call time that no method key is defined by more than one extension.
---@param ... table Classes with `.MT.__index` and `.init` fields
---@return CombinedClass
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
	return result
end

return extend
