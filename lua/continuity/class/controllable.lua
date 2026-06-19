---@class Controllable<T>
---@field on_control      fun(self, cb: fun(state: T), opts?: SubscriptionOpts): fun()
---@field weak_on_control fun(self, cb: fun(state: T), opts?: SubscriptionOpts): fun()

---@class ControllableInternal<T> : Controllable<T>
---@field control_event fun(self, state: T)

local class = require("continuity.class")
local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<ControllableInternal>
local Controllable = class.new({
	methods = {
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
})(function(inst)
	inst._control_cbs = Subscriptions()
end)

return Controllable
