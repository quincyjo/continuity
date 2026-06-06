---@class WeakSubscriptions<T>
---@field add    fun(self, cb: T): integer
---@field remove fun(self, id: integer)
---@field fire   fun(self, ...)
---@field iter   fun(self): fun(table, integer): integer, T

local WeakSubscriptions = {}

WeakSubscriptions.MT = {
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

function WeakSubscriptions.new()
	return setmetatable({ _cbs = setmetatable({}, { __mode = "v" }), _next_id = 1 }, WeakSubscriptions.MT)
end

setmetatable(WeakSubscriptions, {
	__call = function(self)
		return self.new()
	end,
})

return WeakSubscriptions
