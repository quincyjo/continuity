---@class Subscriptions<T>
---@field add      fun(self, cb: T): fun()
---@field weak_add fun(self, cb: T): fun()
---@field fire     fun(self, ...)
---@field iter     fun(self): fun(table, integer): integer, T

local Subscriptions = {}

Subscriptions.MT = {
	__index = {
		add = function(self, cb)
			local id = self._next_id
			self._next_id = id + 1
			self._strong[id] = cb
			return function()
				self._strong[id] = nil
			end
		end,
		weak_add = function(self, cb)
			local id = self._next_id
			self._next_id = id + 1
			self._weak[id] = cb
			return function()
				self._weak[id] = nil
			end
		end,
		fire = function(self, ...)
			for _, cb in pairs(self._strong) do
				cb(...)
			end
			for _, cb in pairs(self._weak) do
				cb(...)
			end
		end,
	},
}

function Subscriptions.new()
	return setmetatable({
		_strong = {},
		_weak = setmetatable({}, { __mode = "v" }),
		_next_id = 1,
	}, Subscriptions.MT)
end

setmetatable(Subscriptions, {
	__call = function(self)
		return self.new()
	end,
})

return Subscriptions
