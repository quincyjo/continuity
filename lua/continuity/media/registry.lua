-- Internal source registry.
-- Manages MediaSource state and dispatches lifecycle callbacks.

---@class PlaybackFlags
---@field can_control?     boolean
---@field can_seek?        boolean
---@field can_go_next?     boolean
---@field can_go_previous? boolean
---@field can_play?        boolean
---@field can_pause?       boolean

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

---@class SourceCapabilities
---@field position? PositionCapability
---@field playback? PlaybackCapability
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

---@class Registry
---@field add                   fun(source_id: string, name: string, initial_state: MediaState, capabilities?: SourceCapabilities, app_name?: string, app_icon?: string)
---@field update                fun(source_id: string, partial_state: MediaState, flags?: PlaybackFlags)
---@field remove                fun(source_id: string)
---@field clear                 fun(source_id: string)
---@field add_dbus_sender       fun(source_id: string, unique_name: string)
---@field sources               fun(): MediaSource[]
---@field on_source_added       fun(cb: fun(source: MediaSource)): fun()
---@field on_source_updated     fun(cb: fun(source: MediaSource), opts: RegistrySubscribeOpts?): fun()
---@field on_source_removed     fun(cb: fun(source_id: string)): fun()
---@field on_playback_action    fun(cb: fun(source: MediaSource, action: PlaybackAction)): fun()
---@field registrar             fun(): SourceRegistrar
---@field PlaybackAction        table<string, PlaybackAction>

---@class RegistrySubscribeOpts
---@field debounce? number  seconds; nil or absent -> immediate (no debounce)

local gears = require("gears")

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
}

--- Create a new registry instance.
---@return Registry
function registry.new()
	---@class RegistryState
	---@field sources                table<string, MediaSource>
	---@field on_added_cbs           fun(source: MediaSource)[]
	---@field on_updated_cbs         fun(source: MediaSource)[]
	---@field on_removed_cbs         fun(source_id: string)[]
	---@field debounced_updated_subs table[]
	---@field position_cbs           table<string, fun(pos: number)[]>
	---@field source_capapabilities  table<string, SourceCapabilities>
	---@field position_stop_fns      table<string, fun()>
	---@field source_cbs             table<string, fun(state: MediaState)[]>
	---@field source_removed_cbs     table<string, fun(source_id: string)[]>
	---@field on_playback_action_cbs fun(source: MediaSource, action: PlaybackAction)[]
	local state = {
		sources = {},
		on_added_cbs = {},
		on_updated_cbs = {},
		on_removed_cbs = {},
		debounced_updated_subs = {},
		position_cbs = {},
		source_capapabilities = {}, -- source_id -> SourceCapabilities
		position_stop_fns = {}, -- source_id -> stop_fn (from capabilities.position.subscribe)
		source_cbs = {},
		source_removed_cbs = {},
		on_playback_action_cbs = {},
	}

	-- Fields whose change signals a track boundary; stale state is cleared on change.
	---@type string[]
	local BOUNDARY_FIELDS = { "track_id", "uri", "title", "artist" }

	---@param cbs function[]
	local function fire(cbs, ...)
		for _, cb in ipairs(cbs) do
			cb(...)
		end
	end

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

	---@param source_id string
	---@param executor PlaybackCapability
	---@param flags PlaybackFlags
	---@return Playback
	local function make_playback(source_id, executor, flags)
		---@param method string Executor method name.
		---@param action PlaybackAction
		---@param guard_passed boolean
		local function dispatch(method, action, guard_passed, ...)
			local src = state.sources[source_id]
			if not guard_passed or not src then
				return
			end
			executor[method](source_id, ...)
			-- TODO: Maybe expose CB with ok and do this after the action?
			fire(state.on_playback_action_cbs, src, action)
		end
		return {
			can_seek = flags.can_seek or false,
			can_go_next = flags.can_go_next or false,
			can_go_previous = flags.can_go_previous or false,
			can_play = flags.can_play or false,
			can_pause = flags.can_pause or false,
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

	local r = {}

	local MediaSourceMeta = {
		__index = {
			active = function(self)
				return self.state.title ~= nil or self.state.status == "playing"
			end,

			subscribe = function(self, cb)
				if not state.source_cbs[self.id] then
					state.source_cbs[self.id] = {}
				end
				local cbs = state.source_cbs[self.id]
				cbs[#cbs + 1] = cb
				return function()
					for i = #cbs, 1, -1 do
						if cbs[i] == cb then
							table.remove(cbs, i)
						end
					end
				end
			end,

			on_removed = function(self, cb)
				if not state.source_removed_cbs[self.id] then
					state.source_removed_cbs[self.id] = {}
				end
				local cbs = state.source_removed_cbs[self.id]
				cbs[#cbs + 1] = cb
				return function()
					for i = #cbs, 1, -1 do
						if cbs[i] == cb then
							table.remove(cbs, i)
						end
					end
				end
			end,
		},
	}

	---@param source_id string
	---@param name string
	---@param initial_state MediaState
	---@param capabilities? SourceCapabilities
	---@param app_name? string
	function r.add(source_id, name, initial_state, capabilities, app_name, app_icon)
		local source =
			{ id = source_id, name = name, state = initial_state or {}, app_name = app_name, app_icon = app_icon }
		setmetatable(source, MediaSourceMeta)

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
							local src = state.sources[source_id]
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
			source.playback = make_playback(source_id, capabilities.playback, capabilities.flags)
		else
			source.playback = nil
		end

		state.sources[source_id] = source
		fire(state.on_added_cbs, source)
	end

	---@param source_id string
	---@param partial_state MediaState
	---@param flags PlaybackFlags?
	function r.update(source_id, partial_state, flags)
		-- TODO: Probably plumb full SourceCapabilities here also.
		if next(partial_state) == nil and flags == nil then
			return
		end
		local source = state.sources[source_id]
		if not source then
			return
		end

		-- Playback boundary detection: clear stale state when track identity changes.
		-- local prev = state.last_boundary[source_id] or {}
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
		-- TODO: there is no recovery path for can_control false->true; r.add must be
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
			end
		end

		-- Route position to fan-out if present.
		local pos_only = false
		if partial_state.position ~= nil then
			pos_only = is_position_only(partial_state, flags)
			fire_position(source_id, partial_state.position)
		end

		-- Material change, update all subscribers.
		if not pos_only then
			fire(state.source_cbs[source_id] or {}, source.state)
			fire(state.on_updated_cbs, source)
			for _, sub in ipairs(state.debounced_updated_subs) do
				if sub.timers[source_id] then
					sub.timers[source_id]:again()
				else
					sub.timers[source_id] = gears.timer({
						timeout = sub.debounce,
						single_shot = true,
						autostart = true,
						callback = function()
							sub.timers[source_id] = nil
							local src = state.sources[source_id]
							if src then
								sub.cb(src)
							end
						end,
					})
				end
			end
		end
	end

	---@param source_id string
	function r.remove(source_id)
		if not state.sources[source_id] then
			return
		end
		for _, sub in ipairs(state.debounced_updated_subs) do
			if sub.timers[source_id] then
				sub.timers[source_id]:stop()
				sub.timers[source_id] = nil
			end
		end
		-- Stop position subscription before clearing state
		if state.position_cbs[source_id] and #state.position_cbs[source_id] > 0 then
			local stop = state.position_stop_fns[source_id]
			if stop then
				stop()
			end
		end
		state.position_cbs[source_id] = nil
		state.position_stop_fns[source_id] = nil
		state.source_capapabilities[source_id] = nil
		state.sources[source_id] = nil
		state.source_cbs[source_id] = nil

		if state.source_removed_cbs[source_id] then
			fire(state.source_removed_cbs[source_id], source_id)
		end
		state.source_removed_cbs[source_id] = nil
		fire(state.on_removed_cbs, source_id)
	end

	---@param source_id string
	function r.clear(source_id)
		local source = state.sources[source_id]
		if not source then
			return
		end
		local keys = {}
		for k in pairs(source.state) do
			keys[#keys + 1] = k
		end
		for _, k in ipairs(keys) do
			source.state[k] = nil
		end
	end

	---@param source_id string
	---@param unique_name string
	function r.add_dbus_sender(source_id, unique_name)
		local source = state.sources[source_id]
		if not source then
			return
		end
		if not source.dbus_senders then
			source.dbus_senders = {}
		end
		source.dbus_senders[unique_name] = true
	end

	---@return MediaSource[]
	function r.sources()
		local list = {}
		for _, source in pairs(state.sources) do
			list[#list + 1] = source
		end
		return list
	end

	---@param cb fun(source: MediaSource)
	---@return fun()
	function r.on_source_added(cb)
		state.on_added_cbs[#state.on_added_cbs + 1] = cb
		return function()
			for i = #state.on_added_cbs, 1, -1 do
				if state.on_added_cbs[i] == cb then
					table.remove(state.on_added_cbs, i)
					break
				end
			end
		end
	end

	---@param cb fun(source: MediaSource)
	---@param opts RegistrySubscribeOpts|nil
	---@return fun()
	function r.on_source_updated(cb, opts)
		if opts and opts.debounce then
			local sub = {
				cb = cb,
				debounce = opts.debounce,
				timers = {},
			}
			state.debounced_updated_subs[#state.debounced_updated_subs + 1] = sub
			return function()
				for i = #state.debounced_updated_subs, 1, -1 do
					if state.debounced_updated_subs[i] == sub then
						table.remove(state.debounced_updated_subs, i)
						break
					end
				end
				for _, t in pairs(sub.timers) do
					t:stop()
				end
			end
		else
			state.on_updated_cbs[#state.on_updated_cbs + 1] = cb
			return function()
				for i = #state.on_updated_cbs, 1, -1 do
					if state.on_updated_cbs[i] == cb then
						table.remove(state.on_updated_cbs, i)
						break
					end
				end
			end
		end
	end

	---@param cb fun(source_id: string)
	---@return fun()
	function r.on_source_removed(cb)
		state.on_removed_cbs[#state.on_removed_cbs + 1] = cb
		return function()
			for i = #state.on_removed_cbs, 1, -1 do
				if state.on_removed_cbs[i] == cb then
					table.remove(state.on_removed_cbs, i)
					break
				end
			end
		end
	end

	---@param cb fun(source: MediaSource, action: PlaybackAction)
	---@return fun()
	function r.on_playback_action(cb)
		state.on_playback_action_cbs[#state.on_playback_action_cbs + 1] = cb
		return function()
			for i = #state.on_playback_action_cbs, 1, -1 do
				if state.on_playback_action_cbs[i] == cb then
					table.remove(state.on_playback_action_cbs, i)
					break
				end
			end
		end
	end

	--- Returns a SourceRegistrar view for use by backends and the coalescer.
	---@return SourceRegistrar
	function r.registrar()
		return {
			add = r.add,
			update = r.update,
			remove = r.remove,
			add_dbus_sender = r.add_dbus_sender,
		}
	end

	return r
end

return registry
