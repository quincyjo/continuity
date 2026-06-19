---@generic T
---@class History<T> : Subscribable<T>
---@field capacity number
---@field count    number
---@field iter     fun(self: History<T>): fun(): T
---@field reset    fun(self: History<T>)
---@field stop     fun(self: History<T>)
---@field start    fun(self: History<T>)

---@class HistoryClass
---@overload fun(source: Subscribable<`T`>, capacity: number): History<`T`>
local History = {}

local class = require("continuity.class")
local Subscribable = require("continuity.class.subscribable")

local HistoryBase = class.new("History"):extends(Subscribable)({
	methods = {
		push = function(self, entry)
			local tail = ((self._head - 1 + self._count) % self.capacity) + 1
			self._buf[tail] = entry
			if self._count == self.capacity then
				self._head = (self._head % self.capacity) + 1
			else
				self._count = self._count + 1
			end
			self.count = self._count
			self.state = entry
			self._subs:fire(entry)
		end,
		iter = function(self)
			local i = 0
			local count = self._count
			local head = self._head
			local capacity = self.capacity
			local buf = self._buf
			return function()
				if i >= count then
					return nil
				end
				local idx = ((head - 1 + i) % capacity) + 1
				i = i + 1
				return buf[idx]
			end
		end,
		reset = function(self)
			self._buf = {}
			self._head = 1
			self._count = 0
			self.count = 0
			self.state = nil
		end,
		stop = function(self)
			if self._unsub then
				self._unsub()
				self._unsub = nil
			end
		end,
		start = function(self)
			if self._unsub then
				return
			end
			self._unsub = self._source:weak_subscribe(function(state)
				self:push(state)
			end)
		end,
	},
	init = function(inst)
		inst._buf = inst._buf or {}
		inst._head = inst._head or 1
		inst._count = inst._count or 0
	end,
})

---@generic T
---@param source   Subscribable<T> The subscribable keep history of.
---@param capacity number          The maximum number of entries to keep.
---@return History<T>
function History.new(source, capacity)
	local h = HistoryBase.new({
		capacity = capacity,
		count = 0,
		_source = source,
		_unsub = nil,
	})
	h:start()
	return h
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(History, {
	__call = function(_, source, capacity)
		return History.new(source, capacity)
	end,
})

return History
