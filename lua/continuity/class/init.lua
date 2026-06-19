---@class CombinableClass<T>
---@field name  string
---@field init  fun(inst?: table): table
---@field new   fun(inst?: table): T

---@class Builder<T>
---@field extends fun(self: Builder<T>, base: CombinableClass): Builder<T>
---@field with    fun(self: Builder<T>, mixin: CombinableClass): Builder<T>
---@overload      fun(spec?: { methods?: table<string, function>, getters?: table<string, function>, init?: fun(inst: table) }): CombinableClass<T>

---@class Class
---@field controllable CombinableClass<Controllable>
---@field removable    CombinableClass<Removable>
---@field subscribable CombinableClass<Subscribable>
local Class = setmetatable({}, {
	__index = function(self, k)
		local mod = require("continuity.class." .. k)
		rawset(self, k, mod)
		return mod
	end,
})

---@param chain { op: string, cls: CombinableClass }[]
---@param name  string
---@param spec  { methods?: table<string, function>, getters?: table<string, function>, init?: fun(inst: table) }?
---@return CombinableClass
local function finalize(chain, name, spec)
	local own_methods = spec and spec.methods or {}
	local own_getters = spec and spec.getters or {}
	local own_init = spec and spec.init

	local methods = {}
	local getters = {}

	for k, v in pairs(own_methods) do
		methods[k] = v
	end
	for k, v in pairs(own_getters) do
		getters[k] = v
	end

	local base_inits = {}
	for i = #chain, 1, -1 do
		local entry = chain[i]
		local cls = entry.cls
		if entry.op == "extends" then
			for k, v in pairs(cls._methods) do
				if methods[k] == nil then
					methods[k] = v
				end
			end
			if cls._getters then
				for k, v in pairs(cls._getters) do
					if getters[k] == nil then
						getters[k] = v
					end
				end
			end
		elseif entry.op == "with" then
			for k, v in pairs(cls._methods) do
				assert(methods[k] == nil, "class extension conflict: " .. tostring(k))
				methods[k] = v
			end
			if cls._getters then
				for k, v in pairs(cls._getters) do
					assert(getters[k] == nil, "class extension getter conflict: " .. tostring(k))
					getters[k] = v
				end
			end
		end
		base_inits[#base_inits + 1] = cls.init
	end

	local full_init
	if #base_inits > 0 or own_init then
		full_init = function(inst)
			inst = inst or {}
			for _, init_fn in ipairs(base_inits) do
				init_fn(inst)
			end
			if own_init then
				own_init(inst)
			end
			return inst
		end
	else
		full_init = function(inst)
			return inst or {}
		end
	end

	local _MT = {
		__index = function(inst, k)
			return methods[k] or (getters[k] and getters[k](inst))
		end,
	}
	local result = {
		name = name,
		init = full_init,
		_methods = methods,
		_getters = getters,
		_MT = _MT,
	}
	result.new = function(inst)
		return setmetatable(result.init(inst), _MT)
	end
	return setmetatable(result, {
		__call = function(_, inst)
			return result.new(inst)
		end,
	})
end

local BuilderMT = {
	__call = function(self, spec)
		return finalize(self._chain, self.name, spec)
	end,
	__index = {
		extends = function(self, base)
			self._chain[#self._chain + 1] = { op = "extends", cls = base }
			return self
		end,
		with = function(self, mixin)
			self._chain[#self._chain + 1] = { op = "with", cls = mixin }
			return self
		end,
	},
}

---@param name string
---@return Builder
function Class.new(name)
	return setmetatable({
		name = name,
		_chain = {},
	}, BuilderMT)
end

--- Pure composition from existing classes. All args are treated as mixins (no conflicts allowed).
---@param name string
---@param ... CombinableClass
---@return CombinableClass
function Class.union(name, ...)
	local args = { ... }
	local builder = Class.new(name)
	for _, cls in ipairs(args) do
		builder:with(cls)
	end
	return builder()
end

return Class
