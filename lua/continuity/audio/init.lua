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
		api = nil,
	},
}, HandleMT)

Audio.Capture = setmetatable({
	id = "Capture",
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
		api = nil,
	},
}, HandleMT)

local bind_inputs, bind_sinks, bind_sources
Audio.inputs, bind_inputs = inputs_mod.new()
Audio.sinks, bind_sinks = devices_mod.new()
Audio.sources, bind_sources = devices_mod.new()

---@param id string
---@param state AudioState
---@param meta AudioDeviceMeta
local function refresh(handle, id, state, meta)
	handle.id = id
	if not handle._private.initialized then
		handle.state = state
		handle.name = meta.name
		handle.description = meta.description
		handle._private.initialized = true
		for _, cb in ipairs(handle._private.on_ready_cbs) do
			cb(handle.state)
		end
		handle._private.on_ready_cbs = nil
	else
		local prev = handle.state
		if
			prev.level ~= state.level
			or prev.muted ~= state.muted
			or prev.port ~= state.port
			or prev.port_type ~= state.port_type
			or prev.connection ~= state.connection
			or handle.name ~= meta.name
			or handle.description ~= meta.description
		then
			handle.state = state
			handle.name = meta.name
			handle.description = meta.description
			for _, cb in ipairs(handle._private.subscribers) do
				cb(handle.state)
			end
		end
	end
end

local function update(handle, level, muted)
	if handle.state.level ~= level or handle.state.muted ~= muted then
		handle.state.level = level
		handle.state.muted = muted
		for _, cb in ipairs(handle._private.subscribers) do
			cb(handle.state)
		end
	end
	for _, cb in ipairs(handle._private.on_control_cbs) do
		cb(handle.state)
	end
end

---@param opts? AudioOpts
function Audio.setup(opts)
	opts = opts or {}
	local backend = opts.backend or require("continuity.audio.backends.pulse")()

	local input_handles = bind_inputs(backend.api.sink_input)
	local sink_handles = bind_sinks(backend.api.sink)
	local source_handles = bind_sources(backend.api.source)

	Audio.Volume._private.api = backend.api.sink
	Audio.Capture._private.api = backend.api.source

	HandleMT.__index.adjust_perc = function(self, delta)
		if delta > 0 and delta + self.state.level > 100 then
			delta = 100 - self.state.level
		elseif delta < 0 and delta + self.state.level < 0 then
			delta = -self.state.level
		end
		if delta == 0 then
			update(self, self.state.level, self.state.muted)
		else
			self._private.api.adjust_perc(self.id, delta, function(level, muted)
				update(self, level, muted)
			end)
		end
	end
	HandleMT.__index.set_perc = function(self, value)
		value = math.max(0, math.min(100, math.floor(value + 0.5)))
		self._private.api.set_perc(self.id, value, function(level, muted)
			update(self, level, muted)
		end)
	end
	HandleMT.__index.toggle_mute = function(self)
		self._private.api.toggle(self.id, function(level, muted)
			update(self, level, muted)
		end)
	end

	backend:start({
		on_sink = function(id, state, meta)
			refresh(Audio.Volume, id, state, meta)
		end,
		on_source = function(id, state, meta)
			refresh(Audio.Capture, id, state, meta)
		end,
		inputs = input_handles,
		sinks = sink_handles,
		sources = source_handles,
	})
end

return Audio
