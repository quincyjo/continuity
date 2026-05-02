---@class SinkInputState
---@field level  integer
---@field muted  boolean
---@field name   string?
---@field sink   integer?

---@class SinkInputMeta
---@field app_name  string?
---@field icon_name string?

---@class SinkInputHandle
---@field id        string
---@field app_name  string?
---@field icon_name string?
---@field state     SinkInputState
---@field subscribe   fun(self: SinkInputHandle, cb: fun(state: SinkInputState)): fun()
---@field on_control  fun(self: SinkInputHandle, cb: fun(state: SinkInputState)): fun()
---@field on_removed  fun(self: SinkInputHandle, cb: fun(id: string)): fun()
---@field adjust_perc fun(self: SinkInputHandle, delta: integer)
---@field set_perc    fun(self: SinkInputHandle, value: number)
---@field toggle_mute fun(self: SinkInputHandle)

---@class InputHandles
---@field add    fun(id: string, state: SinkInputState, meta: SinkInputMeta?)
---@field update fun(id: string, state: SinkInputState)
---@field remove fun(id: string)

local inputs = {}

---@param backend table
---@return table, InputHandles
function inputs.new(backend)
	local state = {
		inputs = {},
		on_added_cbs = {},
		on_updated_cbs = {},
		on_removed_cbs = {},
		subscribers = {},
		on_control_cbs = {},
		handle_removed_cbs = {},
	}

	local function fire(cbs, ...)
		for _, cb in ipairs(cbs) do
			cb(...)
		end
	end

	local function make_unsub(cbs, cb)
		return function()
			for i = #cbs, 1, -1 do
				if cbs[i] == cb then
					table.remove(cbs, i)
					return
				end
			end
		end
	end

	local HandleMT = {
		__index = {
			subscribe = function(self, cb)
				local cbs = state.subscribers[self.id]
				cbs[#cbs + 1] = cb
				return make_unsub(cbs, cb)
			end,

			on_control = function(self, cb)
				local cbs = state.on_control_cbs[self.id]
				cbs[#cbs + 1] = cb
				return make_unsub(cbs, cb)
			end,

			on_removed = function(self, cb)
				local cbs = state.handle_removed_cbs[self.id]
				cbs[#cbs + 1] = cb
				return make_unsub(cbs, cb)
			end,

			adjust_perc = function(self, delta)
				if delta > 0 and delta + self.state.level > 100 then
					delta = 100 - self.state.level
				elseif delta < 0 and delta + self.state.level < 0 then
					delta = -self.state.level
				end
				if delta == 0 then
					fire(state.on_control_cbs[self.id] or {}, self.state)
					return
				end
				backend:adjust_input_perc(self.id, delta, function(level, muted)
					local changed = self.state.level ~= level or self.state.muted ~= muted
					self.state.level = level
					self.state.muted = muted
					if changed then
						fire(state.subscribers[self.id] or {}, self.state)
					end
					fire(state.on_control_cbs[self.id] or {}, self.state)
				end)
			end,

			set_perc = function(self, value)
				value = math.max(0, math.min(100, math.floor(value + 0.5)))
				backend:set_input_perc(self.id, value, function(level, muted)
					local changed = self.state.level ~= level or self.state.muted ~= muted
					self.state.level = level
					self.state.muted = muted
					if changed then
						fire(state.subscribers[self.id] or {}, self.state)
					end
					fire(state.on_control_cbs[self.id] or {}, self.state)
				end)
			end,

			toggle_mute = function(self)
				backend:toggle_input(self.id, function(level, muted)
					local changed = self.state.level ~= level or self.state.muted ~= muted
					self.state.level = level
					self.state.muted = muted
					if changed then
						fire(state.subscribers[self.id] or {}, self.state)
					end
					fire(state.on_control_cbs[self.id] or {}, self.state)
				end)
			end,
		},
	}

	local inst = {}

	function inst.on_added(cb)
		state.on_added_cbs[#state.on_added_cbs + 1] = cb
		return make_unsub(state.on_added_cbs, cb)
	end

	function inst.on_updated(cb)
		state.on_updated_cbs[#state.on_updated_cbs + 1] = cb
		return make_unsub(state.on_updated_cbs, cb)
	end

	function inst.on_removed(cb)
		state.on_removed_cbs[#state.on_removed_cbs + 1] = cb
		return make_unsub(state.on_removed_cbs, cb)
	end

	---@return SinkInputHandle[]
	function inst.all()
		local list = {}
		for _, h in pairs(state.inputs) do
			list[#list + 1] = h
		end
		return list
	end

	local handles = {}

	function handles.add(id, initial_state, meta)
		local handle = setmetatable({
			id = id,
			app_name = meta and meta.app_name,
			icon_name = meta and meta.icon_name,
			state = initial_state or {},
		}, HandleMT)
		state.inputs[id] = handle
		state.subscribers[id] = {}
		state.on_control_cbs[id] = {}
		state.handle_removed_cbs[id] = {}
		fire(state.on_added_cbs, handle)
	end

	function handles.update(id, partial_state)
		local handle = state.inputs[id]
		if not handle then
			return
		end
		local changed = false
		for k, v in pairs(partial_state) do
			if v ~= nil and handle.state[k] ~= v then
				handle.state[k] = v
				changed = true
			end
		end
		if changed then
			fire(state.subscribers[id] or {}, handle.state)
			fire(state.on_updated_cbs, handle)
		end
	end

	function handles.remove(id)
		if not state.inputs[id] then
			return
		end
		fire(state.handle_removed_cbs[id] or {}, id)
		state.inputs[id] = nil
		state.subscribers[id] = nil
		state.on_control_cbs[id] = nil
		state.handle_removed_cbs[id] = nil
		fire(state.on_removed_cbs, id)
	end

	return inst, handles
end

return inputs
