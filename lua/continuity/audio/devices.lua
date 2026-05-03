---@class DeviceCollection
---@field on_added   fun(cb: fun(handle: AudioHandle)): fun()
---@field on_updated fun(cb: fun(handle: AudioHandle)): fun()
---@field on_removed fun(cb: fun(id: string)): fun()
---@field all        fun(): AudioHandle[]

---@class DeviceHandles
---@field add    fun(id: string, state: AudioState, meta: { description: string? }?)
---@field update fun(id: string, state: AudioState)
---@field remove fun(id: string)

local devices = {}

---@param kind DeviceKind
---@return DeviceCollection, fun(backend: AudioBackend): DeviceHandles
function devices.new(kind)
	---@type { handles: table<string, AudioHandle>, subscribers: table<string, fun(state: AudioState)[]>, on_control_cbs: table<string, fun(state: AudioState)[]>, handle_removed_cbs: table<string, fun(id: string)[]>, on_added_cbs: fun(handle: AudioHandle)[], on_updated_cbs: fun(handle: AudioHandle)[], on_removed_cbs: fun(id: string)[] }
	local state = {
		handles = {},
		subscribers = {},
		on_control_cbs = {},
		handle_removed_cbs = {},
		on_added_cbs = {},
		on_updated_cbs = {},
		on_removed_cbs = {},
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
			set_default = function() end,
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

	---@return AudioHandle[]
	function inst.all()
		local list = {}
		for _, h in pairs(state.handles) do
			list[#list + 1] = h
		end
		return list
	end

	local function full_state_changed(old, new)
		return old.level ~= new.level
			or old.muted ~= new.muted
			or old.port ~= new.port
			or old.port_type ~= new.port_type
			or old.connection ~= new.connection
			or old.is_default ~= new.is_default
	end

	local device_handles = {}

	function device_handles.add(id, initial_state, meta)
		local handle = setmetatable({
			id = id,
			description = meta and meta.description,
			state = initial_state or {},
		}, HandleMT)
		state.handles[id] = handle
		state.subscribers[id] = {}
		state.on_control_cbs[id] = {}
		state.handle_removed_cbs[id] = {}
		fire(state.on_added_cbs, handle)
	end

	function device_handles.update(id, new_state)
		local handle = state.handles[id]
		if not handle then
			return
		end
		if full_state_changed(handle.state, new_state) then
			handle.state = new_state
			fire(state.subscribers[id] or {}, handle.state)
			fire(state.on_updated_cbs, handle)
		end
	end

	function device_handles.remove(id)
		if not state.handles[id] then
			return
		end
		fire(state.handle_removed_cbs[id] or {}, id)
		state.handles[id] = nil
		state.subscribers[id] = nil
		state.on_control_cbs[id] = nil
		state.handle_removed_cbs[id] = nil
		fire(state.on_removed_cbs, id)
	end

	local function bind(backend)
		local set_default_method = kind == "sink" and "set_default_sink" or "set_default_source"

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
			backend:adjust_perc(self.id, delta, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.set_perc = function(self, value)
			value = math.max(0, math.min(100, math.floor(value + 0.5)))
			backend:set_perc(self.id, value, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.toggle_mute = function(self)
			backend:toggle(self.id, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.set_default = function(self)
			local fn = backend[set_default_method]
			if not fn then
				return
			end
			fn(backend, self.id, function()
				fire(state.on_control_cbs[self.id] or {}, self.state)
			end)
		end

		return device_handles
	end

	return inst, bind
end

return devices
