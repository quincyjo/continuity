---@class Controllable<T>
---@field on_control      fun(self, cb: fun(state: T), opts?: SubscriptionOpts): fun()
---@field weak_on_control fun(self, cb: fun(state: T), opts?: SubscriptionOpts): fun()

---@class ControllableInternal<T> : Controllable<T>
---@field control_event fun(self, state: T)

local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<ControllableInternal>
local Controllable = {}

Controllable.MT = {
	__index = {
		on_control = function(self, cb, opts)
			return self._control_cbs:add(cb, opts)
		end,
		weak_on_control = function(self, cb, opts)
			return self._control_cbs:weak_add(cb, opts)
		end,
		control_event = function(self, state)
			self._control_cbs:fire(state)
		end,
	},
}

Controllable.methods = Controllable.MT.__index

function Controllable.init(inst)
	inst._control_cbs = Subscriptions()
	return inst
end

function Controllable.new(inst)
	return setmetatable(Controllable.init(inst), Controllable.MT)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Controllable, {
	__call = function(self, inst)
		return self.new(inst)
	end,
})

return Controllable
