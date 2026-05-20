---@class Subscribable<T>
---@field subscribe fun(self, cb: fun(state: T)): fun()
---@field state     T

---@class SubscribableInternal<T> : Subscribable<T>
---@field push fun(self, state: T)

local Subscribable = {}

Subscribable.MT = {
	__index = {
		subscribe = function(self, cb)
			self._subs[#self._subs + 1] = cb
			return function()
				for i = #self._subs, 1, -1 do
					if self._subs[i] == cb then
						table.remove(self._subs, i)
						return
					end
				end
			end
		end,
		push = function(self, state)
			self.state = state
			for _, cb in ipairs(self._subs) do
				cb(state)
			end
		end,
	},
}

Subscribable.methods = Subscribable.MT.__index

function Subscribable.init(inst)
	inst._subs = {}
	return inst
end

return setmetatable(Subscribable, {
	__call = function(self, inst)
		return setmetatable(self.init(inst or {}), self.MT)
	end,
})
