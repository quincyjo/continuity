---@class Subscribable<T>
---@field subscribe      fun(self, cb: fun(state: T)): fun()
---@field weak_subscribe fun(self, cb: fun(state: T)): fun()
---@field state          T

---@class SubscribableInternal<T> : Subscribable<T>
---@field push fun(self, state: T)

local Subscriptions = require("continuity.util.subscriptions")
local WeakSubscriptions = require("continuity.util.weak_subscriptions")

---@type  CombinableClass<SubscribableInternal>
local Subscribable = {}

Subscribable.MT = {
	__index = {
		subscribe = function(self, cb)
			local id = self._subs:add(cb)
			return function()
				self._subs:remove(id)
			end
		end,
		weak_subscribe = function(self, cb)
			local id = self._weak_subs:add(cb)
			return function()
				self._weak_subs:remove(id)
			end
		end,
		push = function(self, state)
			self.state = state
			self._subs:fire(state)
			self._weak_subs:fire(state)
		end,
	},
}

Subscribable.methods = Subscribable.MT.__index

function Subscribable.init(inst)
	inst._subs = Subscriptions()
	inst._weak_subs = WeakSubscriptions()
	return inst
end

function Subscribable.new(inst)
	return setmetatable(Subscribable.init(inst), Subscribable.MT)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Subscribable, {
	__call = function(self, inst)
		return self.new(inst)
	end,
})

return Subscribable
