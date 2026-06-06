---@class Subscriptions<T>
---@field add      fun(self, cb: T): fun()
---@field weak_add fun(self, cb: T): fun()
---@field fire     fun(self, ...)

local Subscriptions = {}

Subscriptions.MT = {
	__index = {
		add = function(self, cb)
			self._strong[cb] = true
			return function()
				self._strong[cb] = nil
			end
		end,
		weak_add = function(self, cb)
			self._weak[cb] = true
			return function()
				self._weak[cb] = nil
			end
		end,
		fire = function(self, ...)
			for cb in pairs(self._strong) do
				cb(...)
			end
			for cb in pairs(self._weak) do
				cb(...)
			end
		end,
	},
}

function Subscriptions.new()
	return setmetatable({
		_strong = {},
		_weak = setmetatable({}, { __mode = "k" }),
	}, Subscriptions.MT)
end

setmetatable(Subscriptions, {
	__call = function(self)
		return self.new()
	end,
})

return Subscriptions
