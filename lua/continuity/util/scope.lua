---@class Scope
---@field subscribe            fun(self, source: Subscribable<`T`>, cb: fun(state: `T`))
---@field weak_subscribe       fun(self, source: Subscribable<`T`>, cb: fun(state: `T`))
---@field on_removed           fun(self, source: Removable<`T`>, cb: fun(id: string))
---@field weak_on_removed      fun(self, source: Removable<`T`>, cb: fun(id: string))
---@field on_control           fun(self, source: Controllable<`T`>, cb: fun(state: `T`))
---@field weak_on_control      fun(self, source: Controllable<`T`>, cb: fun(state: `T`))
---@field on_added             fun(self, source: Observable<`T`>, cb: fun(item: `T`))
---@field weak_on_added        fun(self, source: Observable<`T`>, cb: fun(item: `T`))
---@field on_updated           fun(self, source: Observable<`T`>, cb: fun(item: `T`))
---@field weak_on_updated      fun(self, source: Observable<`T`>, cb: fun(item: `T`))
---@field on_removed           fun(self, source: Observable<`T`>, cb: fun(id: string))
---@field weak_on_removed      fun(self, source: Observable<`T`>, cb: fun(id: string))
---@field connect_signals      fun(self, source: table, signal: string, cb: fun(...))
---@field weak_connect_signals fun(self, source: table, signal: string, cb: fun(...))
---@field dispose              fun(self)

-- newproxy exists in LuaJIT (Lua 5.1 compat) but not in standard Lua 5.3.
-- Lua 5.3 supports __gc on tables directly; LuaJIT requires a userdata proxy.
---@diagnostic disable-next-line: deprecated
local use_gc_proxy = type(newproxy) == "function" -- luacheck: ignore

---@class ScopeClass
---@overload fun(): Scope
local Scope = {}

local function register(self, source, method, cb)
	local n = #self._cbs + 1
	self._cbs[n] = cb
	self._unsubs[n] = source[method](source, cb)
end

Scope.MT = {
	__index = {
		subscribe = function(self, source, cb)
			register(self, source, "subscribe", cb)
		end,
		weak_subscribe = function(self, source, cb)
			register(self, source, "weak_subscribe", cb)
		end,
		on_removed = function(self, source, cb)
			register(self, source, "on_removed", cb)
		end,
		weak_on_removed = function(self, source, cb)
			register(self, source, "weak_on_removed", cb)
		end,
		on_control = function(self, source, cb)
			register(self, source, "on_control", cb)
		end,
		weak_on_control = function(self, source, cb)
			register(self, source, "weak_on_control", cb)
		end,
		on_added = function(self, source, cb)
			register(self, source, "on_added", cb)
		end,
		weak_on_added = function(self, source, cb)
			register(self, source, "weak_on_added", cb)
		end,
		on_updated = function(self, source, cb)
			register(self, source, "on_updated", cb)
		end,
		weak_on_updated = function(self, source, cb)
			register(self, source, "weak_on_updated", cb)
		end,
		connect_signal = function(self, source, signal, cb)
			local n = #self._cbs + 1
			self._cbs[n] = cb
			source:connect_signal(signal, cb)
			self._unsubs[n] = function()
				source:disconnect_signal(signal, cb)
			end
		end,
		weak_connect_signal = function(self, source, signal, cb)
			local n = #self._cbs + 1
			self._cbs[n] = cb
			source:weak_connect_signal(signal, cb)
			self._unsubs[n] = function()
				source:disconnect_signal(signal, cb)
			end
		end,
		dispose = function(self)
			for _, unsub in ipairs(self._unsubs) do
				unsub()
			end
			self._unsubs = {}
			self._cbs = {}
		end,
	},
	__gc = function(self)
		self:dispose()
	end,
}

function Scope.new()
	local inst = setmetatable({
		_unsubs = {},
		_cbs = {},
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
