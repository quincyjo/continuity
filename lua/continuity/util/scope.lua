---@class Scope
---@field connect_signal      fun(self, source: table, signal: string, cb: fun(...))
---@field weak_connect_signal fun(self, source: table, signal: string, cb: fun(...))
---@field dispose             fun(self)

-- Instances are callable: scope(unsub) registers any unsub function for cleanup on dispose.

-- newproxy exists in LuaJIT (Lua 5.1 compat) but not in standard Lua 5.3.
-- Lua 5.3 supports __gc on tables directly; LuaJIT requires a userdata proxy.
---@diagnostic disable-next-line: deprecated
local use_gc_proxy = type(newproxy) == "function" -- luacheck: ignore

---@class ScopeClass
---@overload fun(): Scope
local Scope = {}

Scope.MT = {
	__call = function(self, unsub)
		self._unsubs[unsub] = true
	end,
	__index = {
		connect_signal = function(self, source, signal, cb)
			source:connect_signal(signal, cb)
			self._unsubs[function()
				source:disconnect_signal(signal, cb)
			end] = true
		end,
		weak_connect_signal = function(self, source, signal, cb)
			source:weak_connect_signal(signal, cb)
			self._unsubs[function()
				source:disconnect_signal(signal, cb)
			end] = true
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
		-- LuaJIT path: attach __gc to a userdata proxy that holds inst strongly.
		-- The cycle (inst → proxy → closure → inst) is handled by Lua's mark-and-sweep.
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
