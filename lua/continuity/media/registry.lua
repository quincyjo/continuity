-- Internal source registry.
-- Manages MediaSource state and dispatches lifecycle callbacks.

---@class PlaybackFlags
---@field can_control?     boolean
---@field can_seek?        boolean
---@field can_go_next?     boolean
---@field can_go_previous? boolean
---@field can_play?        boolean
---@field can_pause?       boolean
---@field can_set_volume?  boolean

---@class PlaybackCapability   -- backend executor; one per backend instance; takes source_id
---@field play          fun(source_id: string)
---@field pause         fun(source_id: string)
---@field play_pause    fun(source_id: string)
---@field stop          fun(source_id: string)
---@field next          fun(source_id: string)
---@field previous      fun(source_id: string)
---@field seek          fun(source_id: string, offset_seconds: number)
---@field set_position  fun(source_id: string, pos_seconds: number)

---@class PositionCapability   -- backend executor; one per backend instance; takes source_id
---@field subscribe fun(source_id: string, cb: fun(pos: number)): fun()
---@field get       fun(source_id: string, cb: fun(pos: number|nil))

---@class VolumeCapability   -- backend executor; one per backend instance; takes source_id
---@field set_perc fun(source_id: string, pct: integer)

---@class SourceCapabilities
---@field position? PositionCapability
---@field playback? PlaybackCapability
---@field volume?   VolumeCapability
---@field flags?    PlaybackFlags

---@class SourceRegistrar
---@field add             fun(source_id: string, name: string, state: MediaState, capabilities?: SourceCapabilities, app_name?: string, app_icon?: string)
---@field update          fun(source_id: string, partial_state: MediaState, flags?: PlaybackFlags)
---@field remove          fun(source_id: string)
---@field add_dbus_sender fun(source_id: string, unique_name: string)

---@class Backend
---@field name  string
---@field start fun(self: Backend, reg: SourceRegistrar)
---@field stop  fun(self: Backend)

---@class Registry : Observable<MediaSource>
---@field on_playback_action fun(cb: fun(source: MediaSource, action: PlaybackAction)): fun()
---@field PlaybackAction     table<string, PlaybackAction>

local class = require("continuity.class")
local Subscribable = require("continuity.class.subscribable")
local Removable = require("continuity.class.removable")
local Controllable = require("continuity.class.controllable")
local Observable = require("continuity.observable")

local MediaSource = class
	.new({
		methods = {
			active = function(self)
				return self.state.title ~= nil or self.state.status == "playing"
			end,
		},
	})
	:with(Subscribable)
	:with(Removable)
	:with(Controllable)()

local registry = {}

registry.PlaybackAction = {
	Play = "play",
	Pause = "pause",
	PlayPause = "play_pause",
	Stop = "stop",
	Next = "next",
	Previous = "previous",
	Seek = "seek",
	SetPosition = "set_position",
	SetVolume = "set_volume",
	ToggleMute = "toggle_mute",
}

--- Create a new registry Observable and registrar.
---@return Registry, SourceRegistrar
function registry.new()
	local state = {
		pre_mute_volumes = {}, -- source_id -> volume before muting
		position_cbs = {}, -- source_id -> fun(pos: number)[]
		source_capapabilities = {}, -- source_id -> SourceCapabilities
		position_stop_fns = {}, -- source_id -> stop_fn (from capabilities.position.subscribe)
		on_playback_action_cbs = {},
	}

	-- Fields whose change signals a track boundary; stale state is cleared on change.
	---@type string[]
	local BOUNDARY_FIELDS = { "track_id", "uri", "title", "artist" }

	---@param partial_state MediaState
	---@param flags PlaybackFlags?
	---@return boolean
	local function is_position_only(partial_state, flags)
		if flags ~= nil then
			return false
		end
		local n = 0
		for k in pairs(partial_state) do
			n = n + 1
			if k ~= "position" or n > 1 then
				return false
			end
		end
		return true -- single key "position"
	end

	---@param source_id string
	---@param pos number
	local function fire_position(source_id, pos)
		local cbs = state.position_cbs[source_id]
		if not cbs then
			return
		end
		for _, cb in ipairs(cbs) do
			cb(pos)
		end
	end

	local r = Observable({
		PlaybackAction = registry.PlaybackAction,
		---@param cb fun(source: MediaSource, action: PlaybackAction)
		---@return fun()
		on_playback_action = function(cb)
			state.on_playback_action_cbs[#state.on_playback_action_cbs + 1] = cb
			return function()
				for i = #state.on_playback_action_cbs, 1, -1 do
					if state.on_playback_action_cbs[i] == cb then
						table.remove(state.on_playback_action_cbs, i)
						break
					end
				end
			end
		end,
	})

	---@param source_id string
	---@param executor PlaybackCapability
	---@param flags PlaybackFlags
	---@return Playback
	local function make_playback(source_id, executor, flags, vol_executor)
		---@param method string Executor method name.
		---@param action PlaybackAction
		---@param guard_passed boolean
		local function dispatch(method, action, guard_passed, ...)
			local src = r.items[source_id]
			if not guard_passed or not src then
				return
			end
			executor[method](source_id, ...)
			-- TODO: Maybe expose CB with ok and do this after the action?
			for _, cb in ipairs(state.on_playback_action_cbs) do
				cb(src, action)
			end
			src:control_event(src.state)
		end
		local volume
		if vol_executor and flags.can_set_volume then
			volume = {
				set_perc = function(_, value)
					local src = r.items[source_id]
					if not src then
						return
					end
					vol_executor.set_perc(source_id, value)
					for _, cb in ipairs(state.on_playback_action_cbs) do
						cb(src, registry.PlaybackAction.SetVolume)
					end
				end,
				adjust_perc = function(self, delta)
					local src = r:get(source_id)
					local current = (src and src.state.volume) or 0
					self:set_perc(math.max(0, math.min(100, current + delta)))
				end,
				toggle_mute = function(_)
					local src = r:get(source_id)
					local current = (src and src.state.volume) or 0
					if current > 0 then
						state.pre_mute_volumes[source_id] = current
						vol_executor.set_perc(source_id, 0)
					else
						vol_executor.set_perc(source_id, state.pre_mute_volumes[source_id] or 100)
					end
					for _, cb in ipairs(state.on_playback_action_cbs) do
						cb(src, registry.PlaybackAction.ToggleMute)
					end
				end,
			}
		end
		return {
			can_seek = flags.can_seek or false,
			can_go_next = flags.can_go_next or false,
			can_go_previous = flags.can_go_previous or false,
			can_play = flags.can_play or false,
			can_pause = flags.can_pause or false,
			volume = volume,
			play = function(self)
				dispatch("play", registry.PlaybackAction.Play, self.can_play)
			end,
			pause = function(self)
				dispatch("pause", registry.PlaybackAction.Pause, self.can_pause)
			end,
			play_pause = function(self)
				dispatch("play_pause", registry.PlaybackAction.PlayPause, self.can_play and self.can_pause)
			end,
			stop = function(_)
				dispatch("stop", registry.PlaybackAction.Stop, true)
			end,
			next = function(self)
				dispatch("next", registry.PlaybackAction.Next, self.can_go_next)
			end,
			previous = function(self)
				dispatch("previous", registry.PlaybackAction.Previous, self.can_go_previous)
			end,
			seek = function(self, s)
				dispatch("seek", registry.PlaybackAction.Seek, self.can_seek, s)
			end,
			set_position = function(self, s)
				dispatch("set_position", registry.PlaybackAction.SetPosition, self.can_seek, s)
			end,
		}
	end

	---@param source_id string
	---@param name string
	---@param initial_state MediaState
	---@param capabilities? SourceCapabilities
	---@param app_name? string
	local function register_source(source_id, name, initial_state, capabilities, app_name, app_icon)
		local source = MediaSource.new({
			id = source_id,
			name = name,
			state = initial_state or {},
			app_name = app_name,
			app_icon = app_icon,
		})

		if capabilities then
			state.source_capapabilities[source_id] = capabilities
		end

		source.position = {
			subscribe = function(_, cb)
				if not state.position_cbs[source_id] then
					state.position_cbs[source_id] = {}
				end
				local cbs = state.position_cbs[source_id]
				cbs[#cbs + 1] = cb
				if #cbs == 1 then
					local c = state.source_capapabilities[source_id]
					if c and c.position and c.position.subscribe then
						local stop = c.position.subscribe(source_id, function(pos)
							local src = r:get(source_id)
							if src then
								src.state.position = pos
								fire_position(source_id, pos)
							end
						end)
						state.position_stop_fns[source_id] = stop
					end
				end
				return function()
					for i = #cbs, 1, -1 do
						if cbs[i] == cb then
							table.remove(cbs, i)
							break
						end
					end
					if #cbs == 0 then
						local stop = state.position_stop_fns[source_id]
						if stop then
							stop()
							state.position_stop_fns[source_id] = nil
						end
					end
				end
			end,

			get = function(_, cb)
				local c = state.source_capapabilities[source_id]
				if c and c.position and c.position.get then
					c.position.get(source_id, cb)
				else
					cb(nil)
				end
			end,
		}

		if
			capabilities
			and capabilities.playback
			and capabilities.flags
			and capabilities.flags.can_control ~= false
		then
			source.playback = make_playback(source_id, capabilities.playback, capabilities.flags, capabilities.volume)
		else
			source.playback = nil
		end

		r:add(source)
	end

	---@param source_id string
	---@param partial_state MediaState
	---@param flags PlaybackFlags?
	local function update_source(source_id, partial_state, flags)
		-- TODO: Probably plumb full SourceCapabilities here also.
		if next(partial_state) == nil and flags == nil then
			return
		end
		local source = r.items[source_id]
		if not source then
			return
		end

		-- Playback boundary detection: clear stale state when track identity changes.
		for _, field in ipairs(BOUNDARY_FIELDS) do
			if
				partial_state[field] ~= nil
				and source.state[field] ~= nil
				and partial_state[field] ~= source.state[field]
			then
				-- Keep non-track state, clear track state.
				-- TODO: Consider splitting track data into state.track or state.metadata?
				-- This is a breaking change, so needs to be carefully considered.
				source.state = {
					status = source.state.status,
					volume = source.state.volume,
					shuffle = source.state.shuffle,
					loop = source.state.loop,
				}
				break
			end
		end

		-- Update the source's media state.
		for k, v in pairs(partial_state) do
			if v ~= nil then
				source.state[k] = v
			end
		end

		-- Update playback flags; nil source.playback when can_control becomes false.
		-- TODO: there is no recovery path for can_control false->true; register_source must be
		-- used to (re)construct source.playback with an executor reference.
		if flags then
			if flags.can_control == false then
				source.playback = nil
			elseif source.playback then
				if flags.can_seek ~= nil then
					source.playback.can_seek = flags.can_seek
				end
				if flags.can_go_next ~= nil then
					source.playback.can_go_next = flags.can_go_next
				end
				if flags.can_go_previous ~= nil then
					source.playback.can_go_previous = flags.can_go_previous
				end
				if flags.can_play ~= nil then
					source.playback.can_play = flags.can_play
				end
				if flags.can_pause ~= nil then
					source.playback.can_pause = flags.can_pause
				end
				if flags.can_set_volume == false then
					source.playback.volume = nil
				end
			end
		end

		-- Route position to fan-out if present.
		local pos_only = false
		if partial_state.position ~= nil then
			pos_only = is_position_only(partial_state, flags)
			fire_position(source_id, partial_state.position)
		end

		-- Material change: Observable fires per-source _subs and collection on_updated callbacks.
		if not pos_only then
			r:update(source_id, source.state)
		end
	end

	---@param source_id string
	local function remove_source(source_id)
		if not r.items[source_id] then
			return
		end
		-- Stop position subscription before Observable clears the item.
		if state.position_cbs[source_id] and #state.position_cbs[source_id] > 0 then
			local stop = state.position_stop_fns[source_id]
			if stop then
				stop()
			end
		end
		state.position_cbs[source_id] = nil
		state.position_stop_fns[source_id] = nil
		state.source_capapabilities[source_id] = nil
		state.pre_mute_volumes[source_id] = nil
		r:remove(source_id)
	end

	---@param source_id string
	---@param unique_name string
	local function add_dbus_sender_fn(source_id, unique_name)
		local source = r.items[source_id]
		if not source then
			return
		end
		if not source.dbus_senders then
			source.dbus_senders = {}
		end
		source.dbus_senders[unique_name] = true
	end

	return r,
		{
			add = register_source,
			update = update_source,
			remove = remove_source,
			add_dbus_sender = add_dbus_sender_fn,
		}
end

return registry
