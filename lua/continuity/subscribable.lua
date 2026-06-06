---@class Subscribable<T>
---@field subscribe      fun(self, cb: fun(state: T)): fun()
---@field weak_subscribe fun(self, cb: fun(state: T)): fun()
---@field state          T

---@class SubscribableInternal<T> : Subscribable<T>
---@field push fun(self, state: T)

local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<SubscribableInternal>
local Subscribable = {}

Subscribable.MT = {
	__index = {
		subscribe = function(self, cb)
			return self._subs:add(cb)
		end,
		weak_subscribe = function(self, cb)
			return self._subs:weak_add(cb)
		end,
		push = function(self, state)
			self.state = state
			self._subs:fire(state)
		end,
	},
}

Subscribable.methods = Subscribable.MT.__index

function Subscribable.init(inst)
	inst._subs = Subscriptions()
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
