---@class Subscribable<T>
---@field subscribe fun(self, cb: fun(state: T)): fun()
---@field state     T

---@class SubscribableInternal<T> : Subscribable<T>
---@field push fun(self, state: T)

---@type  CombinableClass<SubscribableInternal>
local Subscribable = {}

Subscribable.MT = {
	__index = {
		subscribe = function(self, cb)
			local id = self._next_id
			self._next_id = id + 1
			self._subs[id] = cb
			return function()
				self._subs[id] = nil
			end
		end,
		push = function(self, state)
			self.state = state
			for _, cb in pairs(self._subs) do
				cb(state)
			end
		end,
	},
}

Subscribable.methods = Subscribable.MT.__index

function Subscribable.init(inst)
	inst._subs = {}
	inst._next_id = 1
	return inst
end

function Subscribable.new(inst)
	return setmetatable(Subscribable.init(inst), Subscribable.MT)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Subscribable, {
	__call = function(self, inst)
		return self.new(inst)
	end,
})

return Subscribable
