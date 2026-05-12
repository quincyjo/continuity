---@alias AudioLevel    integer   Volume level 0–100.
---@alias AudioMuted    boolean   True when the channel is muted.

local inputs_mod = require("continuity.audio.inputs")
local devices_mod = require("continuity.audio.devices")

---@alias AudioCallback fun(state: AudioState)

---@class AudioState
---@field level       AudioLevel
---@field muted       AudioMuted
---@field port        string?  Raw active port name e.g. "analog-input-internal-mic"
---@field port_type?  "headset-mic"|"headset"|"headphones"|"speaker"|"hdmi"|"mic"
---@field connection? "analog"|"bluetooth"|"hdmi"|"usb"
---@field is_default? boolean

---@class AudioHandle
---@field id          string
---@field name        string?
---@field description string?
---@field state       AudioState
---@field on_ready    fun(self: AudioHandle, cb: AudioCallback)
---@field on_control  fun(self: AudioHandle, cb: AudioCallback): fun()
---@field subscribe   fun(self: AudioHandle, cb: AudioCallback): fun()
---@field unsubscribe fun(self: AudioHandle, cb: AudioCallback)
---@field adjust_perc fun(self: AudioHandle, delta: integer)
---@field set_perc    fun(self: AudioHandle, value: number)
---@field toggle_mute fun(self: AudioHandle)
---@field set_default fun(self: AudioHandle)

---@class SinkApi
---@field adjust_perc fun(idx: string, delta: integer, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field set_perc    fun(idx: string, value: number, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field toggle      fun(idx: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field mute        fun(idx: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field unmute      fun(idx: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field set_default fun(idx: string, cb: fun())

---@alias SourceApi SinkApi

---@class SinkInputApi
---@field adjust_perc fun(id: string, delta: integer, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field set_perc    fun(id: string, value: number, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field toggle      fun(id: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field move        fun(input_id: string, sink_id: string|integer, cb: fun())

---@class BackendApi
---@field sink       SinkApi
---@field source     SourceApi
---@field sink_input SinkInputApi

---@class AudioDeviceMeta
---@field name        string?
---@field description string?

---@class AudioBackendOpts
---@field on_sink   fun(id: string, state: AudioState, meta: AudioDeviceMeta)
---@field on_source fun(id: string, state: AudioState, meta: AudioDeviceMeta)
---@field inputs    InputHandles?
---@field sinks     DeviceHandles?
---@field sources   DeviceHandles?

---@class AudioBackend
---@field start fun(self, opts: AudioBackendOpts)
---@field stop  fun(self)?
---@field api   BackendApi

---@class AudioOpts
---@field backend? AudioBackend

local Audio = {}

-- Pre setup metatable for handles. Allows subscribing to events without a
-- backend. All mutation functions do nothing.
local HandleMT = {
	__index = {
		on_ready = function(self, cb)
			if self._private.initialized then
				cb(self.state)
				return
			end
			self._private.on_ready_cbs[#self._private.on_ready_cbs + 1] = cb
		end,
		subscribe = function(self, cb)
			self._private.subscribers[#self._private.subscribers + 1] = cb
			return function()
				self:unsubscribe(cb)
			end
		end,
		on_control = function(self, cb)
			self._private.on_control_cbs[#self._private.on_control_cbs + 1] = cb
			return function()
				for i, sub in ipairs(self._private.on_control_cbs) do
					if sub == cb then
						table.remove(self._private.on_control_cbs, i)
						return
					end
				end
			end
		end,
		unsubscribe = function(self, cb)
			for i, sub in ipairs(self._private.subscribers) do
				if sub == cb then
					table.remove(self._private.subscribers, i)
					return
				end
			end
		end,
		adjust_perc = function(_, _) end,
		set_perc = function(_, _) end,
		toggle_mute = function(_) end,
		set_default = function(_) end,
	},
}

Audio.Volume = setmetatable({
	id = "Master",
	name = nil,
	description = nil,
	state = {
		muted = false,
		level = 0,
	},
	_private = {
		initialized = false,
		on_ready_cbs = {},
		on_control_cbs = {},
		subscribers = {},
		bound_handle = nil,
		bound_unsub = nil,
		bound_control_unsub = nil,
	},
}, HandleMT)

Audio.Capture = setmetatable({
	id = "Capture",
	name = nil,
	description = nil,
	state = {
		muted = false,
		level = 0,
	},
	_private = {
		initialized = false,
		on_ready_cbs = {},
		on_control_cbs = {},
		subscribers = {},
		bound_handle = nil,
		bound_unsub = nil,
		bound_control_unsub = nil,
	},
}, HandleMT)

local bind_inputs, bind_sinks, bind_sources
Audio.inputs, bind_inputs = inputs_mod.new()
Audio.sinks, bind_sinks = devices_mod.new()
Audio.sources, bind_sources = devices_mod.new()

local function find_in_collection(collection_inst, id)
	for _, h in ipairs(collection_inst.all()) do
		if h.id == id then
			return h
		end
	end
	return nil
end

---Bind a pre-made handle to the collection handle for the given device id.
---Creates the collection handle via self-heal if not yet present.
---On device switch: tears down old binding, sets up new one, notifies subscribers.
---On same-device update: only notifies subscribers if metadata changed (state
---changes propagate through the collection forwarder).
local function rebind(handle, id, new_state, meta, collection_inst, collection_device_handles)
	-- Always sync to the collection: creates handle if absent, updates state/meta if present.
	collection_device_handles.add(id, new_state, meta)
	local collection_handle = find_in_collection(collection_inst, id)
	if not collection_handle then
		return
	end

	local new_name = meta and meta.name or nil
	local new_desc = meta and meta.description or nil
	local is_first_bind = not handle._private.initialized
	local is_device_switch = handle._private.bound_handle ~= collection_handle

	if is_device_switch then
		if handle._private.bound_unsub then
			handle._private.bound_unsub()
		end
		if handle._private.bound_control_unsub then
			handle._private.bound_control_unsub()
		end

		handle._private.bound_handle = collection_handle
		handle.id = id
		handle.name = new_name
		handle.description = new_desc
		handle.state = collection_handle.state

		handle._private.bound_unsub = collection_handle:subscribe(function(s)
			handle.state = s
			for _, cb in ipairs(handle._private.subscribers) do
				cb(s)
			end
		end)

		handle._private.bound_control_unsub = collection_handle:on_control(function(s)
			for _, cb in ipairs(handle._private.on_control_cbs) do
				cb(s)
			end
		end)

		if is_first_bind then
			handle._private.initialized = true
			for _, cb in ipairs(handle._private.on_ready_cbs) do
				cb(handle.state)
			end
			handle._private.on_ready_cbs = nil
		else
			for _, cb in ipairs(handle._private.subscribers) do
				cb(handle.state)
			end
		end
	else
		-- Same device. State changes propagate via the collection forwarder.
		-- Only explicitly notify if metadata changed.
		handle.id = id
		if handle.name ~= new_name or handle.description ~= new_desc then
			handle.name = new_name
			handle.description = new_desc
			for _, cb in ipairs(handle._private.subscribers) do
				cb(handle.state)
			end
		end
	end
end

---@param opts? AudioOpts
function Audio.setup(opts)
	opts = opts or {}
	local backend = opts.backend or require("continuity.audio.backends.pulse")()

	local input_handles = bind_inputs(backend.api.sink_input)
	local sink_handles = bind_sinks(backend.api.sink)
	local source_handles = bind_sources(backend.api.source)

	HandleMT.__index.adjust_perc = function(self, delta)
		if self._private.bound_handle then
			self._private.bound_handle:adjust_perc(delta)
		end
	end
	HandleMT.__index.set_perc = function(self, value)
		if self._private.bound_handle then
			self._private.bound_handle:set_perc(value)
		end
	end
	HandleMT.__index.toggle_mute = function(self)
		if self._private.bound_handle then
			self._private.bound_handle:toggle_mute()
		end
	end
	HandleMT.__index.set_default = function(self)
		if self._private.bound_handle then
			self._private.bound_handle:set_default()
		end
	end

	backend:start({
		on_sink = function(id, state, meta)
			rebind(Audio.Volume, id, state, meta, Audio.sinks, sink_handles)
		end,
		on_source = function(id, state, meta)
			rebind(Audio.Capture, id, state, meta, Audio.sources, source_handles)
		end,
		inputs = input_handles,
		sinks = sink_handles,
		sources = source_handles,
	})
end

return Audio
