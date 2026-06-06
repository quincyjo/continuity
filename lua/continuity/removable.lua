---@class Removable
---@field on_removed      fun(self, cb: fun(id: string)): fun()
---@field weak_on_removed fun(self, cb: fun(id: string)): fun()

---@class RemovableInternal : Removable
---@field remove_event fun(self, id: string) Fire all removed callbacks then reset subscription tables.

local Subscriptions = require("continuity.util.subscriptions")
local WeakSubscriptions = require("continuity.util.weak_subscriptions")

---@type CombinableClass<RemovableInternal>
local Removable = {}

Removable.MT = {
	__index = {
		on_removed = function(self, cb)
			local id = self._removed_cbs:add(cb)
			return function()
				self._removed_cbs:remove(id)
			end
		end,
		weak_on_removed = function(self, cb)
			local id = self._weak_removed_cbs:add(cb)
			return function()
				self._weak_removed_cbs:remove(id)
			end
		end,
		remove_event = function(self, id)
			self._removed_cbs:fire(id)
			self._weak_removed_cbs:fire(id)
			Removable.init(self)
		end,
	},
}

Removable.methods = Removable.MT.__index

function Removable.init(inst)
	inst._removed_cbs = Subscriptions()
	inst._weak_removed_cbs = WeakSubscriptions()
	return inst
end

function Removable.new(inst)
	return setmetatable(Removable.init(inst or {}), Removable.MT)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Removable, {
	__call = function(self, inst)
		return self.new(inst)
	end,
})

return Removable
