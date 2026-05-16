---@class ReadyAware<T> : Subscribable<T>
---@field on_ready fun(self, cb: fun(state: T))

---@class ReadyAwareInternal<T> : ReadyAware<T>
---@field push fun(self, state: T)

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
			self._subs[#self._subs + 1] = cb
			return function()
				for i = #self._subs, 1, -1 do
					if self._subs[i] == cb then
						table.remove(self._subs, i)
						return
					end
				end
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
				for _, cb in ipairs(self._subs) do
					cb(state)
				end
			end
		end,
	},
}

ReadyAware.methods = ReadyAware.MT.__index

function ReadyAware.init(inst)
	inst._ready = false
	inst._ready_cbs = {}
	inst._subs = {}
	return inst
end

return setmetatable(ReadyAware, {
	__call = function(self, inst)
		return setmetatable(self.init(inst), self.MT)
	end,
})
