---@class DebouncedSubscriptions<T> A pool of debounced subscriptions.
---@field add      fun(self, cb: T): fun() Registers a callback.
---@field weak_add fun(self, cb: T): fun() Registers callback weakly.
---@field fire     fun(self, ...)          Fire a debounced event.
---@field cancel   fun(self) Cancel all debounced events.
---@field is_empty  boolean Getter for if there are no subscriptions.
---@field non_empty boolean Getter for if there are any subscriptions.

---@diagnostic disable: deprecated
local unpack = unpack or table.unpack

local gears = require("gears")

---@class DebouncedSubscriptionsClass
---@overload fun(debounce: number, when_empty?: fun()): DebouncedSubscriptions
local DebouncedSubscriptions = {}

local methods = {}
local getters = {}

function getters.is_empty(self)
	return not next(self._strong) and not next(self._weak)
end

function getters.non_empty(self)
	return not not (next(self._strong) or next(self._weak))
end

--- Eagerly clear the pool once its last subscriber unsubscribes: there is
--- no one left to receive a pending event, so stop the timer and notify.
local function clear_if_empty(self)
	if getters.is_empty(self) then
		self._timer:stop()
		if self._when_empty then
			self._when_empty()
		end
	end
end

function methods.add(self, cb)
	self._strong[cb] = true
	return function()
		if self._strong[cb] then
			self._strong[cb] = nil
			clear_if_empty(self)
		end
	end
end

function methods.weak_add(self, cb)
	self._weak[cb] = true
	return function()
		if self._weak[cb] then
			self._weak[cb] = nil
			clear_if_empty(self)
		end
	end
end

function methods.fire(self, ...)
	self._event = { ... }
	self._timer:again()
end

function methods.cancel(self)
	self._timer:stop()
end

DebouncedSubscriptions.MT = {
	__index = function(self, k)
		local method = methods[k]
		if method then
			return method
		end
		local getter = getters[k]
		if getter then
			return getter(self)
		end
	end,
}

---@param debounce number
---@param when_empty? fun()
---@return DebouncedSubscriptions
function DebouncedSubscriptions.new(debounce, when_empty)
	local debounced = setmetatable({
		_event = {},
		_strong = {},
		_weak = setmetatable({}, { __mode = "k" }),
		_when_empty = when_empty,
	}, DebouncedSubscriptions.MT)
	debounced._timer = gears.timer({
		timeout = debounce,
		single_shot = true,
		callback = function()
			-- Fallback for weak subscribers GC'd without unsubscribing.
			if debounced.is_empty then
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
