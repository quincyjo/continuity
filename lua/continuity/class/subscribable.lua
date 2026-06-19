---@class Subscribable<T>
---@field subscribe      fun(self, cb: fun(state: T), opts?: SubscriptionOpts): fun()
---@field weak_subscribe fun(self, cb: fun(state: T), opts?: SubscriptionOpts): fun()
---@field state          T
---@field map       fun(self, map: fun(state: T): `S`): Subscribable<`S`>

---@class SubscribableInternal<T> : Subscribable<T>
---@field push fun(self, state: T)

local class = require("continuity.class")
local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<SubscribableInternal>
local Subscribable
Subscribable = class.new("Subscribable")({
	methods = {
		subscribe = function(self, cb, opts)
			return self._subs:add(cb, opts)
		end,
		weak_subscribe = function(self, cb, opts)
			return self._subs:weak_add(cb, opts)
		end,
		push = function(self, state)
			self.state = state
			self._subs:fire(state)
		end,
		map = function(self, map_fn)
			local init_state
			if self.state ~= nil then
				init_state = map_fn(self.state)
			end
			local mapped = Subscribable({
				state = init_state,
				-- We forward subscriptions rather than handling them ourselves.
				-- There are two reasons for this:
				-- 1. If the original Subscribable is destroyed, all
				--    subscriptions will be removed rather than being preserved
				--    in the mapped instance.
				-- 2. This preserves the subscription behavior of the original
				--    Subscribable; EG, maps of Monitors will playback on
				--    subscribe to a mapped Monitor.
				subscribe = function(_, cb)
					return self:subscribe(function(state)
						cb(map_fn(state))
					end)
				end,
				weak_subscribe = function(_, cb)
					return self:weak_subscribe(function(state)
						cb(map_fn(state))
					end)
				end,
			})
			mapped._unsub = self:weak_subscribe(function(state)
				mapped.state = map_fn(state)
			end)
			return mapped
		end,
	},
	init = function(inst)
		inst._subs = Subscriptions()
	end,
})

return Subscribable
