---@class CombinableClass<T>
---@field init  fun(inst?: table): table
---@field new   fun(inst?: table): T

---@class Builder<T>
---@field extends fun(self: Builder<T>, base: CombinableClass): Builder<T>
---@field with    fun(self: Builder<T>, mixin: CombinableClass): Builder<T>
---@overload      fun(init_fn?: fun(inst: table)): CombinableClass<T>

---@class Class
---@overload fun(methods: table<string, function>, getters: table<string, function>): Builder
local Class = {}

---@param builder Builder
---@param init_fn fun(inst: table)?
---@return CombinableClass
local function finalize(builder, init_fn)
	local methods = builder._methods
	local getters = builder._getters
	local base_init = builder._init
	local full_init
	if init_fn then
		full_init = function(inst)
			inst = base_init(inst or {})
			init_fn(inst)
			return inst
		end
	else
		full_init = base_init
	end
	local _MT = {
		__index = function(inst, k)
			return methods[k] or (getters[k] and getters[k](inst))
		end,
	}
	local result = {
		_methods = methods,
		_getters = getters,
		_MT = _MT,
		init = full_init,
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

---@param methods table<string, function>
---@param getters table<string, function>
---@return Builder
local function new_builder(methods, getters)
	local self = {
		_methods = methods or {},
		_getters = getters or {},
		_init = function(inst)
			return inst or {}
		end,
	}

	-- Copies base methods/getters into self for missing keys (self wins).
	-- Chains base.init before accumulated _init so base runs first.
	self.extends = function(_, base)
		for k, v in pairs(base._methods) do
			if self._methods[k] == nil then
				self._methods[k] = v
			end
		end
		if base._getters then
			for k, v in pairs(base._getters) do
				if self._getters[k] == nil then
					self._getters[k] = v
				end
			end
		end
		local prev = self._init
		local base_init = base.init
		self._init = function(inst)
			inst = prev(inst or {})
			return base_init(inst)
		end
		return self
	end

	-- Copies mixin methods/getters into self, asserting no key conflicts.
	-- Chains mixin.init before accumulated _init so mixin runs first.
	self.with = function(_, mixin)
		for k, v in pairs(mixin._methods) do
			assert(self._methods[k] == nil, "class extension conflict: " .. tostring(k))
			self._methods[k] = v
		end
		if mixin._getters then
			for k, v in pairs(mixin._getters) do
				assert(self._getters[k] == nil, "class extension getter conflict: " .. tostring(k))
				self._getters[k] = v
			end
		end
		local prev = self._init
		local mixin_init = mixin.init
		self._init = function(inst)
			inst = prev(inst or {})
			return mixin_init(inst)
		end
		return self
	end

	return setmetatable(self, {
		__call = function(_, init_fn)
			return finalize(self, init_fn)
		end,
	})
end

---@param spec { methods?: table<string, function>, getters?: table<string, function> }
---@return Builder
function Class.new(spec)
	return new_builder(spec and spec.methods or {}, spec and spec.getters or {})
end

--- Pure composition from existing classes. All args are treated as mixins (no conflicts allowed).
---@param ... CombinableClass
---@return CombinableClass
function Class.union(...)
	local args = { ... }
	local methods = {}
	local getters = {}
	local init = function(inst)
		return inst or {}
	end
	for _, cls in ipairs(args) do
		for k, v in pairs(cls._methods) do
			assert(methods[k] == nil, "class.union conflict: " .. tostring(k))
			methods[k] = v
		end
		if cls._getters then
			for k, v in pairs(cls._getters) do
				assert(getters[k] == nil, "class.union getter conflict: " .. tostring(k))
				getters[k] = v
			end
		end
		local prev = init
		local cls_init = cls.init
		init = function(inst)
			inst = prev(inst or {})
			return cls_init(inst)
		end
	end
	local _MT = {
		__index = function(inst, k)
			return methods[k] or (getters[k] and getters[k](inst))
		end,
	}
	local result = {
		_methods = methods,
		_getters = getters,
		_MT = _MT,
		init = init,
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

return Class
