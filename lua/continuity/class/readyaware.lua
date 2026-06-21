---@class ReadyAware<T> : Subscribable<T>
---@field on_ready fun(self, cb: fun(state: T))

---@class ReadyAwareInternal<T> : ReadyAware<T>
---@field push fun(self, state: T)

local class = require("continuity.class")
local Subscribable = require("continuity.class.subscribable")

---@type CombinableClass<ReadyAwareInternal>
local ReadyAware = class.new("ReadyAware"):extends(Subscribable)({
	init = function(inst)
		inst._ready = false
		inst._ready_cbs = {}
	end,
	methods = {
		on_ready = function(self, cb)
			if self._ready then
				cb(self.state)
			else
				self._ready_cbs[#self._ready_cbs + 1] = cb
			end
		end,
		push = function(self, state)
			self.state = state
			if not self._ready then
				self._ready = true
				for _, cb in ipairs(self._ready_cbs) do
					cb(state)
				end
				self._ready_cbs = nil
			else
				self._subs:fire(state)
			end
		end,
	},
})

return ReadyAware
