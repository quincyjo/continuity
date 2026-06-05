---@class Subscribable<T>
---@field subscribe fun(self, cb: fun(state: T)): fun()
---@field state     T
---@field map       fun(self, map: fun(state: T): `S`): Subscribable<`S`>

---@class SubscribableInternal<T> : Subscribable<T>
---@field push fun(self, state: T)

---@type  CombinableClass<SubscribableInternal>
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
		map = function(self, map)
			local mapped = Subscribable({ state = self.state ~= nil and map(self.state) or nil })
			self:subscribe(function(state)
				mapped:push(map(state))
			end)
			return mapped
		end,
	},
}

Subscribable.methods = Subscribable.MT.__index

function Subscribable.init(inst)
	inst._subs = {}
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
