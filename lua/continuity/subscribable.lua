---@class Subscribable<T>
---@field subscribe      fun(self, cb: fun(state: T)): fun()
---@field weak_subscribe fun(self, cb: fun(state: T)): fun()
---@field state          T
---@field map       fun(self, map: fun(state: T): `S`): Subscribable<`S`>

---@class SubscribableInternal<T> : Subscribable<T>
---@field push fun(self, state: T)

local Subscriptions = require("continuity.util.subscriptions")

---@type CombinableClass<SubscribableInternal>
local Subscribable = {}

Subscribable.MT = {
	__index = {
		subscribe = function(self, cb)
			return self._subs:add(cb)
		end,
		weak_subscribe = function(self, cb)
			return self._subs:weak_add(cb)
		end,
		push = function(self, state)
			self.state = state
			self._subs:fire(state)
		end,
		map = function(self, map)
			local init_state
			if self.state ~= nil then
				init_state = map(self.state)
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
						cb(map(state))
					end)
				end,
			})
			self:subscribe(function(state)
				mapped.state = map(state)
			end)
			return mapped
		end,
	},
}

Subscribable.methods = Subscribable.MT.__index

function Subscribable.init(inst)
	inst._subs = Subscriptions()
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
