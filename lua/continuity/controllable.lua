---@class Controllable<T>
---@field on_control fun(self, cb: fun(state: T)): fun()

---@class ControllableInternal<T> : Controllable<T>
---@field control_event fun(self, state: T)

---@type CombinableClass<ControllableInternal>
local Controllable = {}

Controllable.MT = {
	__index = {
		on_control = function(self, cb)
			local id = self._next_id
			self._next_id = id + 1
			self._control_cbs[id] = cb
			return function()
				self._control_cbs[id] = nil
			end
		end,
		control_event = function(self, state)
			for _, cb in pairs(self._control_cbs) do
				cb(state)
			end
		end,
	},
}

Controllable.methods = Controllable.MT.__index

function Controllable.init(inst)
	inst._control_cbs = {}
	inst._next_id = 1
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
