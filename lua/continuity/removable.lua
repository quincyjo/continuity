---@class Removable
---@field on_removed fun(self, cb: fun(id: string)): fun()

local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<Removable>
local Removable = {}

Removable.MT = {
	__index = {
		on_removed = function(self, cb)
			local id = self._removed_cbs:add(cb)
			return function()
				self._removed_cbs:remove(id)
			end
		end,
	},
}

Removable.methods = Removable.MT.__index

function Removable.init(inst)
	inst._removed_cbs = Subscriptions()
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
