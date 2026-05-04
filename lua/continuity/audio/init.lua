---@alias AudioLevel    integer   Volume level 0–100.
---@alias AudioMuted    boolean   True when the channel is muted.
---@alias DeviceKind    "sink"|"source"

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

---@class AudioBackendOpts
---@field on_sink   fun(id: string, state: AudioState)
---@field on_source fun(id: string, state: AudioState)
---@field inputs    InputHandles?
---@field sinks     DeviceHandles?
---@field sources   DeviceHandles?

---@class AudioBackend
---@field start               fun(self, opts: AudioBackendOpts)
---@field adjust_perc         fun(self, name: string, delta: integer, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field set_perc            fun(self, name: string, value: number, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field toggle              fun(self, name: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field mute                fun(self, name: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field unmute              fun(self, name: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field adjust_input_perc?  fun(self, id: string, delta: integer, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field set_input_perc?     fun(self, id: string, value: number, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field toggle_input?       fun(self, id: string, cb: fun(level: AudioLevel, muted: AudioMuted))
---@field move_sink_input?    fun(self, input_id: string, sink_id: string|integer, cb: fun())
---@field set_default_sink?   fun(self, id: string|integer, cb: fun())
---@field set_default_source? fun(self, id: string|integer, cb: fun())

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
	},
}, HandleMT)

local bind_inputs, bind_sinks, bind_sources
Audio.inputs, bind_inputs = inputs_mod.new()
Audio.sinks, bind_sinks = devices_mod.new("sink")
Audio.sources, bind_sources = devices_mod.new("source")

local function refresh(handle, id, state)
	handle.id = id
	if state.description ~= nil then
		handle.description = state.description
	end
	if not handle._private.initialized then
		handle.state = state
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
		then
			handle.state = state
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

	local input_handles = bind_inputs(backend)
	local sink_handles = bind_sinks(backend)
	local source_handles = bind_sources(backend)

	HandleMT.__index.adjust_perc = function(self, delta)
		if delta > 0 and delta + self.state.level > 100 then
			delta = 100 - self.state.level
		elseif delta < 0 and delta + self.state.level < 0 then
			delta = -self.state.level
		end
		if delta == 0 then
			update(self, self.state.level, self.state.muted)
		else
			backend:adjust_perc(self.id, delta, function(level, muted)
				update(self, level, muted)
			end)
		end
	end
	HandleMT.__index.set_perc = function(self, value)
		value = math.max(0, math.min(100, math.floor(value + 0.5)))
		backend:set_perc(self.id, value, function(level, muted)
			update(self, level, muted)
		end)
	end
	HandleMT.__index.toggle_mute = function(self)
		backend:toggle(self.id, function(level, muted)
			update(self, level, muted)
		end)
	end

	backend:start({
		on_sink = function(id, state)
			refresh(Audio.Volume, id, state)
		end,
		on_source = function(id, state)
			refresh(Audio.Capture, id, state)
		end,
		inputs = input_handles,
		sinks = sink_handles,
		sources = source_handles,
	})
end

return Audio
