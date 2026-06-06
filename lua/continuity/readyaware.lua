---@class ReadyAware<T> : Subscribable<T>
---@field on_ready fun(self, cb: fun(state: T))

---@class ReadyAwareInternal<T> : ReadyAware<T>
---@field push fun(self, state: T)

local Subscribable = require("continuity.subscribable")

---@type CombinableClass<ReadyAwareInternal>
local ReadyAware = {}

ReadyAware.MT = {
	__index = {
		on_ready = function(self, cb)
			if self._ready then
				cb(self.state)
			else
				self._ready_cbs[#self._ready_cbs + 1] = cb
			end
		end,
		subscribe = function(self, cb)
			return self._subs:add(cb)
		end,
		weak_subscribe = function(self, cb)
			return self._subs:weak_add(cb)
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
}

ReadyAware.methods = ReadyAware.MT.__index

function ReadyAware.init(inst)
	inst._ready = false
	inst._ready_cbs = {}
	Subscribable.init(inst)
	return inst
end

function ReadyAware.new(inst)
	return setmetatable(ReadyAware.init(inst), ReadyAware.MT)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(ReadyAware, {
	__call = function(self, inst)
		return self.new(inst)
	end,
})

return ReadyAware
