---@generic T : AudioHandle
---@class DeviceCollection<T> : Observable<T>

---@class DeviceHandles
---@field add    fun(id: string, state: AudioState, meta: { name: string?, description: string? }?)
---@field update fun(id: string, state: AudioState)
---@field remove fun(id: string)

local devices = {}

local Observable = require("continuity.observable")
local Controllable = require("continuity.class.controllable")
local Subscribable = require("continuity.class.subscribable")
local Removable = require("continuity.class.removable")
local class = require("continuity.class")

---@generic T : AudioHandle
---@return DeviceCollection<T>, fun(api_sub: SinkApi|SourceApi): DeviceHandles
function devices.new()
	local AudioHandle = class
		.new({
			methods = {
				adjust_perc = function() end,
				set_perc = function() end,
				toggle_mute = function() end,
				set_default = function() end,
				set_port = function() end,
			},
		})
		:with(Subscribable)
		:with(Controllable)
		:with(Removable)()

	---@type ObservableInternal<AudioHandle, AudioState>
	local observable = Observable()

	local function ports_changed(old_ports, new_ports)
		if old_ports == nil and new_ports == nil then
			return false
		end
		if old_ports == nil or new_ports == nil then
			return true
		end
		if #old_ports ~= #new_ports then
			return true
		end
		for i, p in ipairs(old_ports) do
			local np = new_ports[i]
			if p.name ~= np.name or p.availability ~= np.availability then
				return true
			end
		end
		return false
	end

	local function full_state_changed(old, new)
		return old.level ~= new.level
			or old.muted ~= new.muted
			or old.port ~= new.port
			or old.port_type ~= new.port_type
			or old.connection ~= new.connection
			or old.is_default ~= new.is_default
			or ports_changed(old.ports, new.ports)
	end

	local device_handles = {}

	function device_handles.add(id, initial_state, meta)
		if observable:get(id) then
			local handle = observable:get(id)
			if meta then
				handle.name = meta.name
				handle.description = meta.description
			end
			device_handles.update(id, initial_state or {})
			return
		end
		local handle = AudioHandle({
			id = id,
			name = meta and meta.name,
			description = meta and meta.description,
			state = initial_state or { level = 0, muted = false },
		})
		observable:add(handle)
	end

	function device_handles.update(id, new_state)
		local handle = observable:get(id)
		if not handle then
			return
		end
		if full_state_changed(handle.state, new_state) then
			observable:update(id, new_state)
		end
	end

	function device_handles.remove(id)
		local removed = observable:remove(id)
		if removed then
			Controllable.init(removed)
		end
	end

	function device_handles.patch(id, partial)
		local handle = observable:get(id)
		if not handle then
			return nil, nil
		end
		local changed = false
		for k, v in pairs(partial) do
			if handle.state[k] ~= v then
				changed = true
			end
		end
		if changed then
			for k, v in pairs(partial) do
				handle.state[k] = v
			end
			observable:update(id, handle.state)
		end
		return handle.state, { name = handle.name, description = handle.description }
	end

	local function bind(api_sub)
		---@param handle AudioHandle|ControllableInternal<AudioState>
		---@param level AudioLevel
		---@param muted AudioMuted
		local function update_level_muted(handle, level, muted)
			local changed = handle.state.level ~= level or handle.state.muted ~= muted
			handle.state.level = level
			handle.state.muted = muted
			if changed then
				observable:update(handle.id, handle.state)
			end
			handle:control_event(handle.state)
		end

		AudioHandle._methods.adjust_perc = function(self, delta)
			if delta > 0 and delta + self.state.level > 100 then
				delta = 100 - self.state.level
			elseif delta < 0 and delta + self.state.level < 0 then
				delta = -self.state.level
			end
			if delta == 0 then
				self:control_event(self.state)
				return
			end
			api_sub.adjust_perc(self.id, delta, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		AudioHandle._methods.set_perc = function(self, value)
			value = math.max(0, math.min(100, math.floor(value + 0.5)))
			api_sub.set_perc(self.id, value, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		AudioHandle._methods.toggle_mute = function(self)
			api_sub.toggle(self.id, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		AudioHandle._methods.set_default = function(self)
			api_sub.set_default(self.id, function()
				self:control_event(self.state)
			end)
		end

		AudioHandle._methods.set_port = function(self, port)
			local port_name = type(port) == "table" and port.name or port
			api_sub.set_port(self.id, port_name, function()
				self:control_event(self.state)
			end)
		end

		return device_handles
	end

	return observable, bind
end

return devices
