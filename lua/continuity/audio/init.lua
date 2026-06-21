---@alias AudioLevel    integer   Volume level 0–100.
---@alias AudioMuted    boolean   True when the channel is muted.
---@alias AudioPortType "headset-mic"|"headset"|"headphones"|"speaker"|"hdmi"|"mic"

local inputs_mod = require("continuity.audio.inputs")
local devices_mod = require("continuity.audio.devices")
local ReadyAware = require("continuity.class.readyaware")
local Controllable = require("continuity.class.controllable")
local class = require("continuity.class")

---@alias AudioCallback fun(state: AudioState)

---@class AudioControls
---@field adjust_perc fun(self, delta: integer)
---@field set_perc    fun(self, value: AudioLevel)
---@field toggle_mute fun(self)

---@class AudioPort
---@field name         string
---@field description  string
---@field type         AudioPortType?
---@field priority     integer
---@field availability "available"|"not available"|"unknown"

---@class AudioState
---@field level       AudioLevel
---@field muted       AudioMuted
---@field port        string?  Raw active port name e.g. "analog-input-internal-mic"
---@field port_type?  AudioPortType
---@field ports       AudioPort[]?
---@field connection? "analog"|"bluetooth"|"hdmi"|"usb"
---@field is_default? boolean

---@class AudioHandle : AudioControls, Controllable<AudioState>, Subscribable<AudioState>
---@field id          string
---@field name        string?
---@field description string?
---@field state       AudioState
---@field set_default fun(self: AudioHandle)
---@field set_port    fun(self: AudioHandle, port: AudioPort|string)
---@field unsubscribe fun(self: AudioHandle, cb: AudioCallback)

---@alias SinkHandle   AudioHandle
---@alias SourceHandle AudioHandle

---@class SinkApi
---@field adjust_perc fun(idx: string, delta: integer, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field set_perc    fun(idx: string, value: number, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field toggle      fun(idx: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field mute        fun(idx: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field unmute      fun(idx: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field set_default fun(idx: string, cb: fun())
---@field set_port    fun(idx: string, port_name: string, cb: fun())

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

---@class continuity.audio
local Audio = {}

local AudioProxyHandle = class.new("AudioProxyHandle"):with(ReadyAware):with(Controllable)({
	methods = {
		adjust_perc = function(self, delta)
			if self._bound_handle then
				self._bound_handle:adjust_perc(delta)
			end
		end,
		set_perc = function(self, value)
			if self._bound_handle then
				self._bound_handle:set_perc(value)
			end
		end,
		toggle_mute = function(self)
			if self._bound_handle then
				self._bound_handle:toggle_mute()
			end
		end,
		set_default = function(self)
			if self._bound_handle then
				self._bound_handle:set_default()
			end
		end,
		set_port = function(self, port_name)
			if self._bound_handle then
				self._bound_handle:set_port(port_name)
			end
		end,
	},
})

---@type SinkHandle|ReadyAware<AudioState>
Audio.Volume = AudioProxyHandle({
	id = "Master",
	name = nil,
	description = nil,
	state = {
		muted = false,
		level = 0,
	},
	_bound_handle = nil,
	_bound_unsub = nil,
	_bound_control_unsub = nil,
})

---@type SourceHandle|ReadyAware<AudioState>
Audio.Capture = AudioProxyHandle({
	id = "Capture",
	name = nil,
	description = nil,
	state = {
		muted = false,
		level = 0,
	},
	_bound_handle = nil,
	_bound_unsub = nil,
	_bound_control_unsub = nil,
})

local bind_inputs, bind_sinks, bind_sources
---@type InputCollection
Audio.inputs, bind_inputs = inputs_mod.new()
---@type DeviceCollection<SinkHandle|Removable>
Audio.sinks, bind_sinks = devices_mod.new()
---@type DeviceCollection<SourceHandle|Removable>
Audio.sources, bind_sources = devices_mod.new()

---Bind a pre-made handle to the collection handle for the given device id.
---Creates the collection handle via self-heal if not yet present.
---On device switch: tears down old binding, sets up new one, notifies subscribers.
---On same-device update: only notifies subscribers if metadata changed (state
---changes propagate through the collection forwarder).
---@param handle table
---@param id string
---@param new_state AudioState
---@param meta AudioDeviceMeta?
---@param collection_inst DeviceCollection
---@param collection_device_handles DeviceHandles
local function rebind(handle, id, new_state, meta, collection_inst, collection_device_handles)
	---@cast handle ReadyAwareInternal<AudioState>|ControllableInternal<AudioState>|AudioHandle|table
	-- Always sync to the collection: creates handle if absent, updates state/meta if present.
	collection_device_handles.add(id, new_state, meta)
	local collection_handle = collection_inst:get(id)
	if not collection_handle then
		return
	end

	local new_name = meta and meta.name or nil
	local new_desc = meta and meta.description or nil
	local is_device_switch = handle._bound_handle ~= collection_handle

	if is_device_switch then
		if handle._bound_unsub then
			handle._bound_unsub()
		end
		if handle._bound_control_unsub then
			handle._bound_control_unsub()
		end

		handle._bound_handle = collection_handle
		handle.id = id
		handle.name = new_name
		handle.description = new_desc
		handle.state = collection_handle.state

		handle._bound_unsub = collection_handle:subscribe(function(s)
			handle:push(s)
		end)

		handle._bound_control_unsub = collection_handle:on_control(function(s)
			handle:control_event(s)
		end)

		handle:push(handle.state)
	else
		-- Same device. State changes propagate via the collection forwarder.
		-- Only explicitly notify if metadata changed.
		handle.id = id
		if handle.name ~= new_name or handle.description ~= new_desc then
			handle.name = new_name
			handle.description = new_desc
			handle:push(handle.state)
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
