---@class Removable
---@field on_removed fun(self, cb: fun(id: string)): fun()

---@type CombinableClass<Removable>
local Removable = {}

Removable.MT = {
	__index = {
		on_removed = function(self, cb)
			local id = self._next_id
			self._next_id = id + 1
			self._removed_cbs[id] = cb
			return function()
				self._removed_cbs[id] = nil
			end
		end,
	},
}

Removable.methods = Removable.MT.__index

function Removable.init(inst)
	inst._removed_cbs = {}
	inst._next_id = 1
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
