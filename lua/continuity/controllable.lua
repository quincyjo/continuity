---@class Controllable<T>
---@field on_control      fun(self, cb: fun(state: T)): fun()
---@field weak_on_control fun(self, cb: fun(state: T)): fun()

---@class ControllableInternal<T> : Controllable<T>
---@field control_event fun(self, state: T)

---@type CombinableClass<ControllableInternal>
local Subscriptions = require("continuity.util.subscriptions")
local WeakSubscriptions = require("continuity.util.weak_subscriptions")

local Controllable = {}

Controllable.MT = {
	__index = {
		on_control = function(self, cb)
			local id = self._control_cbs:add(cb)
			return function()
				self._control_cbs:remove(id)
			end
		end,
		weak_on_control = function(self, cb)
			local id = self._weak_control_cbs:add(cb)
			return function()
				self._weak_control_cbs:remove(id)
			end
		end,
		control_event = function(self, state)
			self._control_cbs:fire(state)
			self._weak_control_cbs:fire(state)
		end,
	},
}

Controllable.methods = Controllable.MT.__index

function Controllable.init(inst)
	inst._control_cbs = Subscriptions()
	inst._weak_control_cbs = WeakSubscriptions()
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
