---@class Removable
---@field on_removed      fun(self, cb: fun(id: string)): fun()
---@field weak_on_removed fun(self, cb: fun(id: string)): fun()

local class = require("continuity.class")
local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<Removable>
local Removable
Removable = class.new("Removable")({
	init = function(inst)
		inst._removed_cbs = Subscriptions()
	end,
	teardown = function(inst)
		inst._removed_cbs:fire(inst.id)
		Subscriptions.teardown(inst._removed_cbs)
	end,
	methods = {
		on_removed = function(self, cb)
			return self._removed_cbs:add(cb)
		end,
		weak_on_removed = function(self, cb)
			return self._removed_cbs:weak_add(cb)
		end,
	},
})

return Removable
