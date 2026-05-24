---@class Removable
---@field on_removed fun(self, cb: fun(id: string)): fun()

local Removable = {}

Removable.MT = {
	__index = {
		on_removed = function(self, cb)
			self._removed_cbs[#self._removed_cbs + 1] = cb
			return function()
				for i = #self._removed_cbs, 1, -1 do
					if self._removed_cbs[i] == cb then
						table.remove(self._removed_cbs, i)
						return
					end
				end
			end
		end,
	},
}

Removable.methods = Removable.MT.__index

function Removable.init(inst)
	inst._removed_cbs = {}
	return inst
end

function Removable.new(inst)
	return setmetatable(Removable.init(inst or {}), Removable.MT)
end

return setmetatable(Removable, {
	__call = function(self, inst)
		return self.new(inst)
	end,
})
