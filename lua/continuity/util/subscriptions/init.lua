---@class SubscriptionOpts
---@field debounce? number  seconds; nil or absent -> immediate (no debounce)

---@class Subscriptions<T> A collection of subscriptions to an event.
---@field add       fun(self, cb: T, opts?: SubscriptionOpts): fun() Registers a callback.
---@field weak_add  fun(self, cb: T, opts?: SubscriptionOpts): fun() Registers callback weakly.
---@field debounced fun(self, debounce: number): DebouncedSubscriptions<T>
---@field fire      fun(self, ...) Fire an event, notifying all callbacks.
---@field cancel    fun(self) Cancel all debounced events.
---@field is_empty  boolean Getter for if there are no subscriptions.
---@field non_empty boolean Getter for if there are any subscriptions.

---@class SubscriptionsClass : CombinableClass<Subscriptions>
---@field debounced DebouncedSubscriptionsClass
---@overload fun(): Subscriptions

local class = require("continuity.class")

---@type SubscriptionsClass
local Subscriptions
Subscriptions = class.new("Subscriptions")({
	init = function(inst)
		inst._debounced = {}
		inst._strong = {}
		inst._weak = setmetatable({}, { __mode = "k" })
	end,
	teardown = function(inst)
		for _, debounced in pairs(inst._debounced) do
			debounced:cancel()
		end
		inst._debounced = {}
		inst._strong = {}
		inst._weak = setmetatable({}, { __mode = "k" })
	end,
	methods = {
		debounced = function(self, debounce)
			if self._debounced[debounce] then
				return self._debounced[debounce]
			end
			local debounced = Subscriptions.debounced(debounce, function()
				self._debounced[debounce] = nil
			end)
			self._debounced[debounce] = debounced
			return debounced
		end,
		add = function(self, cb, opts)
			if not opts or not opts.debounce then
				self._strong[cb] = true
				return function()
					self._strong[cb] = nil
				end
			else
				return self:debounced(opts.debounce):add(cb)
			end
		end,
		weak_add = function(self, cb, opts)
			if not opts or not opts.debounce then
				self._weak[cb] = true
				return function()
					self._weak[cb] = nil
				end
			else
				return self:debounced(opts.debounce):weak_add(cb)
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
		cancel = function(self)
			for _, debounced in pairs(self._debounced) do
				debounced:cancel()
			end
		end,
	},
	getters = {
		is_empty = function(self)
			return not next(self._strong) and not next(self._weak) and not next(self._debounced)
		end,
		non_empty = function(self)
			return not not (next(self._strong) or next(self._weak) or next(self._debounced))
		end,
	},
})

-- Static, not an instance method/getter.
-- The type checker can't express "a CombinableClass with one extra static field" cleanly.
---@diagnostic disable-next-line: assign-type-mismatch, inject-field
Subscriptions.debounced = require("continuity.util.subscriptions.debounced")

return Subscriptions
