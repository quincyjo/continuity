---@class DebouncedSubscriptions<T> A pool of debounced subscriptions.
---@field add      fun(self, cb: T): fun() Registers a callback.
---@field weak_add fun(self, cb: T): fun() Registers callback weakly.
---@field fire     fun(self, ...)          Fire a debounced event.

---@diagnostic disable: deprecated
local unpack = unpack or table.unpack

local gears = require("gears")

---@class DebouncedSubscriptionsClass
---@overload fun(debounce: number, when_empty?: fun()): DebouncedSubscriptions
local DebouncedSubscriptions = {}

DebouncedSubscriptions.MT = {
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
			self._event = { ... }
			self._timer:again()
		end,
	},
}

---@param debounce number
---@param when_empty? fun()
---@return DebouncedSubscriptions
function DebouncedSubscriptions.new(debounce, when_empty)
	local debounced = setmetatable({
		_event = {},
		_strong = {},
		_weak = setmetatable({}, { __mode = "k" }),
	}, DebouncedSubscriptions.MT)
	debounced._timer = gears.timer({
		timeout = debounce,
		single_shot = true,
		callback = function()
			if not next(debounced._strong) and not next(debounced._weak) then
				if when_empty then
					when_empty()
				end
				return
			end
			for cb in pairs(debounced._strong) do
				cb(unpack(debounced._event))
			end
			for cb in pairs(debounced._weak) do
				cb(unpack(debounced._event))
			end
		end,
	})
	return debounced
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(DebouncedSubscriptions, {
	__call = function(self, ...)
		return self.new(...)
	end,
})

return DebouncedSubscriptions
