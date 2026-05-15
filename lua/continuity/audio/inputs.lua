---@class SinkInputState
---@field level  AudioLevel
---@field muted  AudioMuted
---@field name   string?
---@field sink   integer?
---@field corked boolean

---@class SinkInputMeta
---@field app_name  string?
---@field icon_name string?
---@field app_icon  string?
---@field role      string?
---@field binary    string?

---@class SinkInputHandle : Subscribable<SinkInputState>, AudioControls<SinkInputState>
---@field id          string
---@field app_name    string?
---@field icon_name   string?
---@field app_icon    string?
---@field role        string?
---@field binary      string?
---@field state       SinkInputState
---@field on_removed  fun(self: SinkInputHandle, cb: fun(id: string)): fun()
---@field move_to     fun(self: SinkInputHandle, target: SinkHandle|integer|string)

---@class InputHandles
---@field add    fun(id: string, state: SinkInputState, meta: SinkInputMeta?)
---@field update fun(id: string, state: SinkInputState)
---@field remove fun(id: string)

---@class InputCollection : Observable<SinkInputHandle>

local inputs = {}

---@return InputCollection, fun(api_sub: SinkInputApi): InputHandles
function inputs.new()
	---@type { inputs: table<string, SinkInputHandle>, subscribers: table<string, fun(state: SinkInputState)[]>, on_control_cbs: table<string, fun(state: SinkInputState)[]>, handle_removed_cbs: table<string, fun(id: string)[]>, on_added_cbs: fun(handle: SinkInputHandle)[], on_updated_cbs: fun(handle: SinkInputHandle)[], on_removed_cbs: fun(id: string)[] }
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

			adjust_perc = function() end,
			set_perc = function() end,
			toggle_mute = function() end,
			move_to = function() end,
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
			app_icon = meta and meta.app_icon,
			role = meta and meta.role,
			binary = meta and meta.binary,
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

	local function bind(api_sub)
		local function update_level_muted(handle, level, muted)
			local changed = handle.state.level ~= level or handle.state.muted ~= muted
			handle.state.level = level
			handle.state.muted = muted
			if changed then
				fire(state.subscribers[handle.id] or {}, handle.state)
			end
			fire(state.on_control_cbs[handle.id] or {}, handle.state)
		end

		HandleMT.__index.adjust_perc = function(self, delta)
			if delta > 0 and delta + self.state.level > 100 then
				delta = 100 - self.state.level
			elseif delta < 0 and delta + self.state.level < 0 then
				delta = -self.state.level
			end
			if delta == 0 then
				fire(state.on_control_cbs[self.id] or {}, self.state)
				return
			end
			api_sub.adjust_perc(self.id, delta, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.set_perc = function(self, value)
			value = math.max(0, math.min(100, math.floor(value + 0.5)))
			api_sub.set_perc(self.id, value, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.toggle_mute = function(self)
			api_sub.toggle(self.id, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.move_to = function(self, target)
			local sink_id = type(target) == "table" and target.id or target
			api_sub.move(self.id, sink_id, function()
				fire(state.on_control_cbs[self.id] or {}, self.state)
			end)
		end

		return handles
	end

	return inst, bind
end

return inputs
