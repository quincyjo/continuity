---@class Scope
---@field register            fun(self, unsub: fun()): fun()
---@field connect_signal      fun(self, source: table, signal: string, cb: fun(...)): fun()
---@field weak_connect_signal fun(self, source: table, signal: string, cb: fun(...)): fun()
---@field dispose             fun(self)
---@overload fun(unsub: fun()): fun()

-- newproxy exists in LuaJIT (Lua 5.1 compat) but not in standard Lua 5.3.
-- Lua 5.3 supports __gc on tables directly; LuaJIT requires a userdata proxy.
---@diagnostic disable-next-line: deprecated
local use_gc_proxy = type(newproxy) == "function" -- luacheck: ignore

---@class ScopeClass
---@overload fun(): Scope
local Scope = {}

Scope.MT = {
	__call = function(self, unsub)
		return self:register(unsub)
	end,
	__index = {
		register = function(self, unsub)
			self._unsubs[unsub] = true
			return function()
				self._unsubs[unsub] = nil
				unsub()
			end
		end,
		connect_signal = function(self, source, signal, cb)
			source:connect_signal(signal, cb)
			local unsub = function()
				source:disconnect_signal(signal, cb)
			end
			self._unsubs[unsub] = true
			return function()
				self._unsubs[unsub] = nil
				unsub()
			end
		end,
		weak_connect_signal = function(self, source, signal, cb)
			source:weak_connect_signal(signal, cb)
			local unsub = function()
				source:disconnect_signal(signal, cb)
			end
			self._unsubs[unsub] = true
			return function()
				self._unsubs[unsub] = nil
				unsub()
			end
		end,
		dispose = function(self)
			for unsub in pairs(self._unsubs) do
				unsub()
			end
			self._unsubs = {}
		end,
	},
	__gc = function(self)
		self:dispose()
	end,
}

function Scope.new()
	local inst = setmetatable({
		_unsubs = {},
	}, Scope.MT)
	if use_gc_proxy then
		---@diagnostic disable-next-line: deprecated
		local proxy = newproxy(true)
		getmetatable(proxy).__gc = function()
			inst:dispose()
		end
		inst._gc_proxy = proxy
	end
	return inst
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Scope, {
	__call = function(self)
		return self.new()
	end,
})

return Scope
