---@class Controllable<T>
---@field on_control fun(self, cb: fun(state: T)): fun()

---@class ControllableInternal<T> : Controllable<T>
---@field control_event fun(self, state: T)

---@type CombinableClass<ControllableInternal>
local Controllable = {}

Controllable.MT = {
	__index = {
		on_control = function(self, cb)
			self._control_cbs[#self._control_cbs + 1] = cb
			return function()
				for i = #self._control_cbs, 1, -1 do
					if self._control_cbs[i] == cb then
						table.remove(self._control_cbs, i)
						return
					end
				end
			end
		end,
		control_event = function(self, state)
			for _, cb in ipairs(self._control_cbs) do
				cb(state)
			end
		end,
	},
}

Controllable.methods = Controllable.MT.__index

function Controllable.init(inst)
	inst._control_cbs = {}
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
