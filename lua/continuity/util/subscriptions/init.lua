---@class SubscriptionOpts
---@field debounce? number  seconds; nil or absent -> immediate (no debounce)

---@class Subscriptions<T> A collection of subscriptions to an event.
---@field add      fun(self, cb: T, opts?: SubscriptionOpts): fun() Registers a callback.
---@field weak_add fun(self, cb: T, opts?: SubscriptionOpts): fun() Registers callback weakly.
---@field fire     fun(self, ...) Fire an event, notifying all callbacks.

---@class SubscriptionsClass
---@field debounced DebouncedSubscriptionsClass
---@overload fun(): Subscriptions
local Subscriptions = {
	---@diagnostic disable-next-line: assign-type-mismatch
	debounced = require("continuity.util.subscriptions.debounced"),
}

local function get_debounced_pool(subscriptions, debounce)
	if subscriptions._debounced[debounce] then
		return subscriptions._debounced[debounce]
	end
	local debounced = Subscriptions.debounced(debounce, function()
		subscriptions._debounced[debounce] = nil
	end)
	subscriptions._debounced[debounce] = debounced
	return debounced
end

Subscriptions.MT = {
	__index = {
		add = function(self, cb, opts)
			if not opts or not opts.debounce then
				self._strong[cb] = true
				return function()
					self._strong[cb] = nil
				end
			else
				local debounced = get_debounced_pool(self, opts.debounce)
				return debounced:add(cb)
			end
		end,
		weak_add = function(self, cb, opts)
			if not opts or not opts.debounce then
				self._weak[cb] = true
				return function()
					self._weak[cb] = nil
				end
			else
				local debounced = get_debounced_pool(self, opts.debounce)
				return debounced:weak_add(cb)
			end
		end,
		fire = function(self, ...)
			for cb in pairs(self._strong) do
				cb(...)
			end
			for cb in pairs(self._weak) do
				cb(...)
			end
			for _, debounced in pairs(self._debounced) do
				debounced:fire(...)
			end
		end,
	},
}

function Subscriptions.new()
	return setmetatable({
		_debounced = {},
		_strong = {},
		_weak = setmetatable({}, { __mode = "k" }),
	}, Subscriptions.MT)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Subscriptions, {
	__call = function(self)
		return self.new()
	end,
})

return Subscriptions
