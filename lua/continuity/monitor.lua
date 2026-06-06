---@class MonitorBackend<T>
---@field start fun(self, cb: fun(state: T))
---@field stop  fun(self)

---@class MonitorOptions<T>
---@field backend? MonitorBackend<T>

---@generic T, O: MonitorOptions<T>
---@class Monitor<T, O> : Subscribable<T>
---@field name  string
---@field setup fun(opts?: O)
---@field state T|nil
---@field stop  fun()
---@field protected backend?   MonitorBackend<T>
---@field protected configure  fun(self, opts: O): MonitorBackend<T> Resolve configuration to a backend.
---@field protected on_update? fun(self, state, T): T Hook to modify state before it is pushed.
---@field protected cleanup?   fun(self) Cleanup after stop.

local gears = require("gears")
local Subscribable = require("continuity.subscribable")

---@class MonitorClass
---@overload fun(inst: table): Monitor
local Monitor = {}

Monitor.MT = {
	__index = {
		subscribe = function(self, cb)
			local unsub = self._subs:add(cb)
			if self.state ~= nil then
				cb(self.state)
			end
			return unsub
		end,
		weak_subscribe = function(self, cb)
			local unsub = self._subs:weak_add(cb)
			if self.state ~= nil then
				cb(self.state)
			end
			return unsub
		end,
		push = Subscribable.methods.push,
	},
}

Monitor.methods = Monitor.MT.__index

function Monitor.init(inst)
	inst = inst or {}
	Subscribable.init(inst)
	inst.state = nil
	inst._started = false
	if not inst.setup then
		inst.setup = function(opts)
			if inst._started then
				gears.debug.print_warning(
					(inst.name or "Unnamed") .. " monitor: setup() called more than once; ignoring"
				)
				return
			end
			inst._started = true
			inst.backend = inst:configure(opts)
			inst.backend:start(function(state)
				if inst.on_update then
					state = inst:on_update(state)
				end
				inst:push(state)
			end)
		end
	end
	if not inst.stop then
		inst.stop = function()
			inst._started = false
			if inst.backend then
				inst.backend:stop()
				inst.backend = nil
			end
			Monitor.init(inst)
			if inst.cleanup then
				inst:cleanup()
			end
		end
	end
	return inst
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Monitor, {
	__call = function(self, inst)
		return setmetatable(self.init(inst), self.MT)
	end,
})

return Monitor
