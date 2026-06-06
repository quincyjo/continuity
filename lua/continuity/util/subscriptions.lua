---@class Subscriptions<T>
---@field add    fun(self, cb: T): integer
---@field remove fun(self, id: integer)
---@field fire   fun(self, ...)
---@field iter   fun(self): fun(table, integer): integer, T

local Subscriptions = {}

Subscriptions.MT = {
	__index = {
		add = function(self, cb)
			local id = self._next_id
			self._next_id = id + 1
			self._cbs[id] = cb
			return id
		end,
		remove = function(self, id)
			self._cbs[id] = nil
		end,
		fire = function(self, ...)
			for _, cb in pairs(self._cbs) do
				cb(...)
			end
		end,
		iter = function(self)
			return pairs(self._cbs)
		end,
	},
}

function Subscriptions.new()
	return setmetatable({ _cbs = {}, _next_id = 1 }, Subscriptions.MT)
end

setmetatable(Subscriptions, {
	__call = function(self)
		return self.new()
	end,
})

return Subscriptions
