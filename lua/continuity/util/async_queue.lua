--- A simple queue of async events that guarantees linear execution of their
--- side effects. Note that the side effect of an event should not complete
--- another event, as that will cause double executions. Events and their
--- effects must be independent.

---@class AsyncQueueItem      An async event in the queue.
---@field done     boolean    If the async event has been completed.
---@field ok?      boolean    If the async event completed successfully.
---@field effect?  fun()      The side effect to execute when the async event is completed.
---@field queue    AsyncQueue The queue this item belongs to.
---@field complete fun(ok: boolean, effect?: fun()) Complete the async event.

---@class AsyncQueue                   A queue of async events that guarantees linear execution.
---@field submit fun(): AsyncQueueItem Add an async event to the queue.
---@field flush fun()                  Flush the queue of completed async events.

local AsyncQueue = {}

local AsyncQueueItemMT = {
	__index = {
		complete = function(self, ok, effect)
			self.done = true
			self.ok = ok
			self.effect = effect
			self.queue:flush()
		end,
	},
}

local AsyncQueueMT = {
	__index = {
		submit = function(self)
			local item = setmetatable({
				done = false,
				queue = self,
			}, AsyncQueueItemMT)
			self._private.queue[#self._private.queue + 1] = item
			return item
		end,

		flush = function(self)
			local flushed = 0
			for i, item in ipairs(self._private.queue) do
				if item.done then
					flushed = i
					if item.effect then
						item.effect()
					end
				else
					break
				end
			end
			if flushed > 0 then
				local new_queue = {}
				for i = flushed + 1, #self._private.queue do
					new_queue[#new_queue + 1] = self._private.queue[i]
				end
				self._private.queue = new_queue
			end
		end,
	},
}

---@return AsyncQueue
function AsyncQueue.new()
	return setmetatable({
		_private = {
			queue = {},
		},
	}, AsyncQueueMT)
end

return setmetatable(AsyncQueue, {
	__call = function(_)
		return AsyncQueue.new()
	end,
}) ---@type AsyncQueue
