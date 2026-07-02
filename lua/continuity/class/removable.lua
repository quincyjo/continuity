---@class Removable
---@field on_removed      fun(self, cb: fun(id: string)): fun()
---@field weak_on_removed fun(self, cb: fun(id: string)): fun()

---@class RemovableInternal : Removable
---@field remove_event fun(self, id: string) Fire all removed callbacks then reset subscription tables.

local class = require("continuity.class")
local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<RemovableInternal>
local Removable
Removable = class.new("Removable")({
	init = function(inst)
		inst._removed_cbs = Subscriptions()
	end,
	methods = {
		on_removed = function(self, cb)
			return self._removed_cbs:add(cb)
		end,
		weak_on_removed = function(self, cb)
			return self._removed_cbs:weak_add(cb)
		end,
		remove_event = function(self, id)
			self._removed_cbs:fire(id)
			Removable.init(self)
		end,
	},
})

return Removable
