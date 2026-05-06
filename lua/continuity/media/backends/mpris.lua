-- MPRIS backend.
-- Discovers MPRIS2 players on the D-Bus session bus and monitors them for
-- PropertiesChanged signals. One D-Bus player name = one source.

local awful = require("awful")
local gears = require("gears")
local Process = require("continuity.util.process")
local menubar_utils = require("menubar.utils")
local grep = require("continuity.tools.grep")

---@class MprisOpts
---@field service_name_xdg_lookup? table<string, string> Map of XDG name to service name pattern.

local mpris = {}

-- Private exports for testability.
local _private = {}
mpris._private = _private

---@param props table
---@return PlaybackFlags
function _private.parse_can_flags(props)
	return {
		can_control = props.CanControl ~= false,
		can_seek = props.CanSeek ~= false,
		can_go_next = props.CanGoNext ~= false,
		can_go_previous = props.CanGoPrevious ~= false,
		can_play = props.CanPlay ~= false,
		can_pause = props.CanPause ~= false,
	}
end

---@type table<string, string>
local CAN_FLAG_KEYS = {
	CanControl = "can_control",
	CanSeek = "can_seek",
	CanGoNext = "can_go_next",
	CanGoPrevious = "can_go_previous",
	CanPlay = "can_play",
	CanPause = "can_pause",
}

--- Parse only the Can* keys present in props. Returns nil if none are present.
--- Used for delta updates where only changed flags should be forwarded.
---@param props table
---@return PlaybackFlags|nil
function _private.parse_can_flags_partial(props)
	local flags = {}
	local any = false
	for dbus_key, flag_key in pairs(CAN_FLAG_KEYS) do
		if props[dbus_key] ~= nil then
			flags[flag_key] = props[dbus_key] ~= false
			any = true
		end
	end
	return any and flags or nil
end

---@type table<string, PlaybackStatus>
local PLAYBACK_MAP = { Playing = "playing", Paused = "paused", Stopped = "stopped" }
---@type table<string, PlaybackLoop>
local LOOP_MAP = { None = "none", Track = "track", Playlist = "playlist" }

--- Extract player name from D-Bus service name.
---@param service_name string  e.g. "org.mpris.MediaPlayer2.spotify"
---@return string
function _private.parse_player_name(service_name)
	return service_name:match("org%.mpris%.MediaPlayer2%.(.+)$") or service_name
end

--- Parse a Metadata property dict into a partial MediaState.
---@param props table
---@return MediaState
function _private.parse_metadata(props)
	local state = {}
	state.title = props["xesam:title"]
	state.album = props["xesam:album"]
	state.uri = props["xesam:url"]
	state.art_uri = props["mpris:artUrl"]
	state.track_id = props["mpris:trackid"]
	state.track_number = props["xesam:trackNumber"]
	state.disc_number = props["xesam:discNumber"]

	local function join_or_string(v)
		if type(v) == "table" then
			return table.concat(v, ", ")
		elseif type(v) == "string" then
			return v
		end
	end
	state.artist = join_or_string(props["xesam:artist"])
	state.album_artist = join_or_string(props["xesam:albumArtist"])

	if props["mpris:length"] then
		state.duration = props["mpris:length"] / 1000000
	end

	return state
end

--- Parse playback-related properties into a partial MediaState.
---@param props table
---@return MediaState
function _private.parse_playback_props(props)
	local state = {}
	if props.PlaybackStatus ~= nil then
		state.status = PLAYBACK_MAP[props.PlaybackStatus]
	end
	if props.Volume ~= nil then
		state.volume = math.floor(props.Volume * 100)
	end
	if props.Shuffle ~= nil then
		state.shuffle = props.Shuffle
	end
	if props.LoopStatus ~= nil then
		state.loop = LOOP_MAP[props.LoopStatus]
	end
	if props.Position ~= nil then
		state.position = props.Position / 1000000
	end
	return state
end

--- Extract the content between a balanced pair of [ ] brackets, starting from
--- the first [ at or after position `from` in `str`.
--- Returns the content string (without outer brackets), or nil if not found
--- and the position after the closing bracket.
---@param str string
---@param from integer
---@return string|nil,integer|nil
local function extract_balanced(str, from)
	local bracket_start = str:find("%[", from)
	if not bracket_start then
		return nil, nil
	end
	local depth = 0
	local i = bracket_start
	while i <= #str do
		local c = str:sub(i, i)
		if c == "[" then
			depth = depth + 1
		elseif c == "]" then
			depth = depth - 1
			if depth == 0 then
				return str:sub(bracket_start + 1, i - 1), i + 1
			end
		end
		i = i + 1
	end
	return nil, nil
end

--- Parse scalar and array fields from a dbus-send text block into `props`.
--- Called on both the top-level output and recursively on the Metadata block.
---@param text string
---@param props table  mutated in place
local function parse_block(text, props)
	-- Scalar strings. Use [^\n]* (greedy, non-newline) so that embedded
	-- double-quotes in the value are included: the engine backtracks to the
	-- last " before end-of-line rather than stopping at the first inner ".
	for key, val in text:gmatch('"([%w:]+)"%s+variant%s+string%s+"([^\n]*)"') do
		props[key] = val
	end
	-- Object paths (e.g. mpris:trackid from Firefox). Treat as strings.
	for key, val in text:gmatch('"([%w:]+)"%s+variant%s+object path%s+"([^\n]*)"') do
		props[key] = val
	end
	-- int32 / int64 / uint64
	for key, val in text:gmatch('"([%w:]+)"%s+variant%s+u?int%d+%s+(%d+)') do
		props[key] = tonumber(val)
	end
	-- double
	for key, val in text:gmatch('"([%w:]+)"%s+variant%s+double%s+([%d%.]+)') do
		props[key] = tonumber(val)
	end
	-- boolean
	for key, val in text:gmatch('"([%w:]+)"%s+variant%s+boolean%s+(%a+)') do
		props[key] = (val == "true")
	end
	-- String arrays: use bracket-counting to avoid stopping at nested ]
	---@type integer|nil
	local pos = 1
	while pos do
		-- Find next "key" variant array pattern
		local ks, ke, key = text:find('"([%w:]+)"%s+variant%s+array', pos)
		if not ks or not ke then
			break
		end
		local content, next_pos = extract_balanced(text, ke)
		if content then
			local items = {}
			for s in content:gmatch('"([^"]*)"') do
				items[#items + 1] = s
			end
			if #items > 0 then
				props[key] = items
			end
			pos = next_pos
		else
			pos = ke + 1
		end
	end
end

---@alias DbusSendType "method_call"|"signal"

---@class DbusArgs
---@field object_path string
---@field interface_member string
---@field dest string
---@field content? string|string[]
---@field print_reply? boolean
---@field type? DbusSendType

---@param args DbusArgs
---@param cb? fun(stdout: string|nil, exitcode: integer)
local function dbus_send(args, cb)
	local cmd = {
		"dbus-send",
		"--session",
		"--reply-timeout=3000",
		"--dest=" .. args.dest,
	}
	if args.print_reply then
		cmd[#cmd + 1] = "--print-reply"
	end
	if args.type then
		cmd[#cmd + 1] = "--type=" .. args.type
	end
	cmd[#cmd + 1] = args.object_path
	cmd[#cmd + 1] = args.interface_member
	---@diagnostic disable-next-line assign-type-mismatch
	local contents = type(args.content) == "table" and args.content or args.content and { args.content } or {}
	-- Shouldn't be needed but LSP can't resolve the array narrowing from type == table.
	---@cast contents string[]
	for _, v in ipairs(contents) do
		cmd[#cmd + 1] = v
	end
	awful.spawn.easy_async(cmd, function(stdout, stderr, exitreason, exitcode)
		if exitcode ~= 0 then
			gears.debug.print_warning(
				string.format(
					"media.mpris: dbus-send %s failed for %s:%s@%s with contents [%s] (%s:%d): %s",
					args.type or "signal",
					args.object_path,
					args.interface_member,
					args.dest,
					table.concat(contents, ", "),
					exitreason,
					exitcode,
					stderr
				)
			)
		end
		if cb then
			cb(exitcode == 0 and stdout or nil, exitcode)
		end
	end)
end

---@param service_name string
---@param interface string
---@param property string
---@param cb function(property)
local function get_interface_property(service_name, interface, property, cb)
	dbus_send({
		print_reply = true,
		dest = service_name,
		object_path = "/org/mpris/MediaPlayer2",
		interface_member = "org.freedesktop.DBus.Properties.Get",
		content = { "string:org.mpris." .. interface, property },
	}, cb)
end

---@param service_name string
---@param property string
---@param cb function(property)
local function get_player_property(service_name, property, cb)
	get_interface_property(service_name, "MediaPlayer2.Player", property, cb)
end

---@param method string
---@param service_name string
---@param content? string|string[]
---@param cb? function(stdout: string|nil, exitcode: integer)
local function player_method(method, service_name, content, cb)
	dbus_send({
		type = "method_call",
		dest = service_name,
		object_path = "/org/mpris/MediaPlayer2",
		interface_member = "org.mpris.MediaPlayer2.Player." .. method,
		content = content,
	}, cb)
end

--- Fetch all properties for a player and push them to the registry.
---@param service_name string
---@param cb fun(state?: MediaState, capabilities?: PlaybackFlags)
local function player_get_all(service_name, cb)
	dbus_send({
		type = "method_call",
		print_reply = true,
		dest = service_name,
		object_path = "/org/mpris/MediaPlayer2",
		interface_member = "org.freedesktop.DBus.Properties.GetAll",
		content = { "string:org.mpris.MediaPlayer2.Player" },
	}, function(stdout)
		if stdout then
			local state = {}
			local props = _private.parse_dbus_output(stdout)
			for k, v in pairs(_private.parse_metadata(props)) do
				state[k] = v
			end
			for k, v in pairs(_private.parse_playback_props(props)) do
				state[k] = v
			end
			local can_flags = _private.parse_can_flags(props)
			cb(state, can_flags)
		else
			cb(nil, nil)
		end
	end)
end

--- Parse dbus-send --print-reply output into a flat props table.
--- Handles fields nested inside the Metadata variant array block, which is
--- how Spotify (and most MPRIS players) structure GetAll output.
--- Exported for testability — this is the highest-risk parsing path.
---@param stdout string
---@return table
function _private.parse_dbus_output(stdout)
	local props = {}

	-- Parse top-level playback fields (PlaybackStatus, Volume, Shuffle, etc.)
	parse_block(stdout, props)

	-- Extract the Metadata variant array block using bracket-counting, then
	-- parse xesam:* and mpris:* fields from within it. This is necessary because
	-- a lazy regex would stop at the first ] inside the Metadata block, before
	-- reaching the xesam:artist array entry.
	local meta_start = stdout:find('"Metadata"%s+variant%s+array')
	if meta_start then
		local meta_content = extract_balanced(stdout, meta_start)
		if meta_content then
			parse_block(meta_content, props)
		end
	end

	return props
end

--- Parse a dbus-monitor PropertiesChanged signal record into changed props and
--- invalidated property names. The record is a multi-line string starting with
--- the signal header line. Returns nil on parse failure.
--- Exported for testability.
---@param record string  complete signal record (header + body lines)
---@return {sender_line: string, props: table, invalidated: string[]}|nil
function _private.parse_properties_changed(record)
	if not record or #record == 0 then
		return nil
	end
	local sender_line = record:match("^[^\n]+") or ""

	-- First array [...] is the changed-properties dict.
	local changed_content, pos2 = extract_balanced(record, 1)
	if not changed_content then
		return nil
	end
	local props = {}
	parse_block(changed_content, props)
	local meta_start = changed_content:find('"Metadata"%s+variant%s+array')
	if meta_start then
		local meta_content = extract_balanced(changed_content, meta_start)
		if meta_content then
			parse_block(meta_content, props)
		end
	end

	-- Second array [...] is the invalidated-properties list.
	local invalidated = {}
	local inv_content = pos2 and extract_balanced(record, pos2)
	if inv_content then
		for s in inv_content:gmatch('"([^"]*)"') do
			invalidated[#invalidated + 1] = s
		end
	end

	return { sender_line = sender_line, props = props, invalidated = invalidated }
end

--- Extract the MPRIS service name from a dbus-monitor signal header line.
--- Matches the well-known MPRIS name directly, or resolves a unique bus
--- name (:1.xxx) via unique_name_map. Returns nil for non-MPRIS lines.
--- Exported for testability.
---@param line string
---@param unique_name_map table  unique bus name -> well-known service name
---@return string|nil
function _private.sender_service(line, unique_name_map)
	local well_known = line:match("sender=(org%.mpris%.MediaPlayer2%.[^%s,]+)")
	if well_known then
		return well_known
	end
	local unique = line:match("sender=(:[%d%.]+)")
	if unique then
		return unique_name_map[unique]
	end
end

--- Extract the unique bus name from a GetNameOwner dbus-send reply.
--- Exported for testability.
---@param stdout string
---@return string|nil
function _private.parse_unique_name(stdout)
	return stdout:match('string "(:[%d%.]+)"')
end

--- Extract the DesktopEntry value from a dbus-send Properties.Get reply.
--- Exported for testability.
---@param stdout string
---@return string|nil
function _private.parse_desktop_entry(stdout)
	return stdout:match('variant%s+string%s+"([^"]+)"')
end

--- Map well-known MPRIS service names to their corresponding DesktopEntry
--- values, which are used to resolve the application icon if fetching
--- DesktopEntry fails.
---@type table<string, string>
local default_service_name_xdg_lookup = {
	-- Chrome has a bug and errors when requesting desktop entry.
	["google-chrome"] = "^chromium%.instance.*",
	-- Luakit returns an empty string.
	luakit = "^org%.luakit%.Sandboxed%.instance-.*",
	-- Firefox works correctly, so this is just for completeness.
	firefox = "^firefox%.instance.*",
	-- Workaround for Spotify failing to provide desktop entry at startup.
	["com.spotify.Client"] = "spotify",
}

--- Resolve the application icon for a given desktop entry name.
--- First tries menubar.utils.lookup_icon(entry) directly. If that returns nil,
--- greps dirs for a .desktop file whose Name= matches entry (case-insensitive),
--- then reads its Icon= field and resolves that via lookup_icon.
--- This fallback is required for players that report an invalid DesktopEntry
--- value such as Spotify on flatpak reporting "spotify" instead of
--- "com.spotify.Client". Exported for testability.
---@param entry string   e.g. "spotify" from MPRIS DesktopEntry property
---@param dirs  string[] directories to search (e.g. menu_gen.all_menu_dirs)
---@param cb    fun(icon_path: string|nil)
function _private.resolve_app_icon(entry, dirs, cb)
	local direct = menubar_utils.lookup_icon(entry)
	if direct then
		cb(direct)
		return
	end
	grep({
		pattern = "^Name=" .. entry,
		path = dirs,
		case_insensitive = true,
		follow_links = true,
		include = "*.desktop",
	}, function(results, _)
		if not results or #results == 0 then
			cb(nil)
			return
		end
		local desktop_file = results[1].filepath
		grep({
			pattern = "^Icon=",
			path = { desktop_file },
			follow_links = true,
		}, function(icon_results, _)
			if not icon_results or #icon_results == 0 then
				cb(nil)
				return
			end
			local icon_name = icon_results[1].text:match("^Icon=(.+)$")
			cb(icon_name and menubar_utils.lookup_icon(icon_name) or nil)
		end)
	end)
end

--- Factory — returns a Backend instance.
---@param opts? MprisOpts
---@return Backend
local function create_backend(opts)
	---@type SourceRegistrar
	local registry
	---@type table<string, string>
	local known_players = {} -- service_name -> source_id
	---@type table<string, string>
	local unique_name_map = {} -- unique bus name (:1.xxx) -> service_name
	---@type table<string, string>
	local reverse_players = {} -- source_id -> service_name
	---@type table<string, table>
	local position_timers = {} -- source_id -> gears.timer
	---@type table<string, string>
	local track_ids = {} -- source_id -> current mpris:trackid

	--- Map of source id to all registered position callbacks.
	---@type table<string, fun(pos: number)[]>
	local position_callbacks = {}

	--- Map of pending service names in add process. Refresh player will push
	--- here if occupied. This queues changes so that add_player has the newest
	--- state. This is to guard against MPRIS timeouts when the monitor
	--- outpaces application startup.
	---@type table<string, {state: MediaState, flags: PlaybackFlags}|true>
	local pending_adds = {}

	local service_name_xdg_lookup = opts and opts.service_name_xdg_lookup or default_service_name_xdg_lookup

	---@param name string MPRIS media player name.
	---@return string|nil The desktop alias if found, nil otherwise.
	local function resolve_alias(name)
		for alias, regex in pairs(service_name_xdg_lookup) do
			if name:match(regex) then
				return alias
			end
		end
		return nil
	end

	---@type table<string, integer>
	local refresh_id = {}

	--- Fetch all properties for a player and push them to the registry.
	---@param service_name string
	---@param source_id string
	---@param reg SourceRegistrar
	local function refresh_player(service_name, source_id, reg)
		local id = (refresh_id[source_id] or 0) + 1
		refresh_id[source_id] = id
		player_get_all(service_name, function(state, can_flags)
			-- Only the newest refresh is valid.
			if not state or id ~= refresh_id[source_id] then
				return
			end
			track_ids[source_id] = state.track_id
			if state or can_flags then
				if pending_adds[service_name] then
					pending_adds[service_name] = {
						state = state,
						flags = can_flags,
					}
				else
					reg.update(source_id, state or {}, can_flags)
				end
			end
		end)
	end

	--- Remove a position callback. Cleans up the timer if all callbacks are
	--- removed.
	---@param source_id string
	---@param cb fun(pos: number)
	local function remove_position_callback(source_id, cb)
		for i = #position_callbacks[source_id], 1, -1 do
			if position_callbacks[source_id][i] == cb then
				table.remove(position_callbacks[source_id], i)
			end
		end
		if #position_callbacks[source_id] == 0 and position_timers[source_id] then
			position_timers[source_id]:stop()
			position_timers[source_id] = nil
		end
	end

	---@param source_id string
	---@param cb fun(pos: number)
	---@return fun()
	local function subscribe_position(source_id, cb)
		local service_name = reverse_players[source_id]
		if not service_name then
			return function() end
		end
		if not position_callbacks[source_id] then
			position_callbacks[source_id] = {}
		end
		table.insert(position_callbacks[source_id], cb)
		if not position_timers[source_id] then
			position_timers[source_id] = gears.timer({
				timeout = 1,
				autostart = true,
				callback = function()
					get_player_property(service_name, "string:Position", function(stdout)
						if stdout then
							local micros = stdout:match("int64%s+(%d+)")
							if micros then
								for _, f in ipairs(position_callbacks[source_id] or {}) do
									f(tonumber(micros) / 1000000)
								end
							end
						end
					end)
				end,
			})
		end
		return function()
			remove_position_callback(source_id, cb)
		end
	end

	---@param source_id string
	---@param cb fun(pos: number|nil)
	local function get_position(source_id, cb)
		local service_name = reverse_players[source_id]
		if not service_name then
			cb(nil)
			return
		end
		get_player_property(service_name, "string:Position", function(stdout)
			if stdout then
				local micros = stdout:match("int64%s+(%d+)")
				cb(micros and tonumber(micros) / 1000000 or nil)
			else
				cb(nil)
			end
		end)
	end

	---@type PositionCapability
	local position_capability = {
		subscribe = subscribe_position,
		get = get_position,
	}

	---@type PlaybackCapability
	local playback_capability = {
		play = function(id)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'play' called with unknown source_id: " .. tostring(id))
				return
			end
			player_method("Play", svc)
		end,
		pause = function(id)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'pause' called with unknown source_id: " .. tostring(id))
				return
			end
			player_method("Pause", svc)
		end,
		play_pause = function(id)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'play_pause' called with unknown source_id: " .. tostring(id))
				return
			end
			player_method("PlayPause", svc)
		end,
		stop = function(id)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'stop' called with unknown source_id: " .. tostring(id))
				return
			end
			player_method("Stop", svc)
		end,
		next = function(id)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'next' called with unknown source_id: " .. tostring(id))
				return
			end
			player_method("Next", svc)
		end,
		previous = function(id)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'previous' called with unknown source_id: " .. tostring(id))
				return
			end
			-- Work around for previous restarting a track.
			-- TODO: This seems to be slow or the position isn't yet observable.
			-- Seek works to immediately update, but this seems to wait for the next position poll.
			player_method("Previous", svc, nil, function()
				get_position(id, function(pos)
					registry.update(id, { position = pos })
				end)
			end)
		end,
		seek = function(id, offset_seconds)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'seek' called with unknown source_id: " .. tostring(id))
				return
			end
			player_method("Seek", svc, string.format("int64:%d", math.floor(offset_seconds * 1e6)), function()
				get_position(id, function(pos)
					registry.update(id, { position = pos })
				end)
			end)
		end,
		set_position = function(id, pos_seconds)
			local svc = reverse_players[id]
			if not svc then
				gears.debug.print_warning("media.mpris: 'set_position' called with unknown source_id: " .. tostring(id))
				return
			end
			local tid = track_ids[id]
			if not tid then
				return
			end
			player_method(
				"SetPosition",
				svc,
				{ "objpath:" .. tid, string.format("int64:%d", math.floor(pos_seconds * 1e6)) },
				function()
					registry.update(id, { position = pos_seconds })
				end
			)
		end,
	}

	---@param service_name string
	local function add_player(service_name)
		if known_players[service_name] then
			return
		end
		local player_name = _private.parse_player_name(service_name)
		local name = player_name
		local source_id = "mpris:" .. player_name

		-- We make as known right away so that PropertiesChanged detection can
		-- push updated to the pending_adds queue.
		known_players[service_name] = source_id
		reverse_players[source_id] = service_name

		local app_icon_done = false
		---@type string|nil
		local app_icon
		local get_all_done = false
		pending_adds[service_name] = true

		local function finish()
			if app_icon_done and get_all_done then
				local pending = pending_adds[service_name] or {}
				local state = pending.state or {}
				local capabilities = pending.flags
				track_ids[source_id] = state.track_id
				local caps = {
					position = position_capability,
					playback = capabilities and capabilities.can_control and playback_capability or nil,
					flags = capabilities,
				}
				registry.add(source_id, name, state, caps, name, app_icon)
				pending_adds[service_name] = nil
			end
		end

		player_get_all(service_name, function(s, caps)
			-- In case a PropertiesChanged event finished first somehow.
			if pending_adds[service_name] == true then
				pending_adds[service_name] = {
					state = s,
					flags = caps,
				}
			end
			get_all_done = true
			finish()
		end)

		-- TODO: Have observed where this request happens "too fast" with
		-- Spotify, and it takes until timeout. The pending adds queue allows
		-- the initial add to be up to date, but the app icon is still missing.
		-- This is a bug in Spotify that it exposes the player and then fails
		-- to respond to the desktop entry request. I don't see a clean
		-- solution. Maybe making the app icon separate from the add like DBus
		-- sender and having some "service not yet ready" single retry?
		-- Or remove the parallelization and do this after GetAll since that
		-- seems to not have this problem, but may still happen.
		-- Exit 1 but org.freedesktop.DBus.Error.NoReply could be grepped.
		dbus_send({
			type = "method_call",
			print_reply = true,
			dest = service_name,
			object_path = "/org/mpris/MediaPlayer2",
			interface_member = "org.freedesktop.DBus.Properties.GetAll",
			content = { "string:org.mpris.MediaPlayer2" },
		}, function(stdout)
			if stdout then
				local props = _private.parse_dbus_output(stdout)
				if props.Identity and #props.Identity > 0 then
					name = props.Identity
				end
				local entry = (not props.DesktopEntry or #props.DesktopEntry == 0) and resolve_alias(player_name)
					or props.DesktopEntry
				if entry then
					require("continuity.util.app_icon").by_desktop_entry(entry, function(icon_path)
						-- TODO: Maybe extend backwards compat for Spotify flatpak by name discovery?
						-- _private.resolve_app_icon(entry, menu_gen.all_menu_dirs, function(icon_path)
						app_icon_done = true
						app_icon = icon_path
						finish()
					end)
					return
				end
			end
			app_icon_done = true
			finish()
		end)

		-- Map the unique bus name so the monitor can resolve signals sent with
		-- the unique name (e.g. ":1.122") instead of the well-known MPRIS name.
		-- Also register it as a D-Bus sender on the source for notification suppression.
		dbus_send({
			print_reply = true,
			dest = "org.freedesktop.DBus",
			object_path = "/org/freedesktop/DBus",
			interface_member = "org.freedesktop.DBus.GetNameOwner",
			content = { "string:" .. service_name },
		}, function(stdout2)
			if stdout2 then
				local unique = _private.parse_unique_name(stdout2)
				if unique then
					unique_name_map[unique] = service_name
					registry.add_dbus_sender(source_id, unique)
				end
			end
		end)
	end

	---@param service_name string
	local function remove_player(service_name)
		local source_id = known_players[service_name]
		if not source_id then
			return
		end
		if position_timers[source_id] then
			position_timers[source_id]:stop()
			position_timers[source_id] = nil
		end
		reverse_players[source_id] = nil
		known_players[service_name] = nil
		registry.remove(source_id)
		for unique, svc in pairs(unique_name_map) do
			if svc == service_name then
				unique_name_map[unique] = nil
			end
		end
	end

	local function discover_players()
		dbus_send({
			print_reply = true,
			dest = "org.freedesktop.DBus",
			object_path = "/org/freedesktop/DBus",
			interface_member = "org.freedesktop.DBus.ListNames",
		}, function(stdout)
			if stdout then
				for name in stdout:gmatch('"(org%.mpris%.MediaPlayer2%.[^"]+)"') do
					add_player(name)
				end
			end
		end)
	end

	-- PropertiesChanged monitor.
	-- Accumulates lines into records, dispatching each one as soon as its two
	-- top-level array blocks are structurally complete (depth returns to 0
	-- twice). Falls back to GetAll when invalidated_properties is non-empty or
	-- an add is still in flight. The "signal " header acts as a safety flush
	-- only (handles malformed/incomplete prior records).
	local monitor_buffer = {}
	local monitor_depth = 0
	local monitor_arrays_closed = 0

	local function dispatch_record()
		if #monitor_buffer == 0 then
			return
		end
		local record = table.concat(monitor_buffer, "\n")
		monitor_buffer = {}
		local r = _private.parse_properties_changed(record)
		if not r then
			return
		end
		local svc = _private.sender_service(r.sender_line, unique_name_map)
		local source_id = svc and known_players[svc]
		if not source_id then
			return
		end
		if #r.invalidated > 0 or pending_adds[svc] then
			refresh_player(svc, source_id, registry)
			return
		end
		local state = {}
		for k, v in pairs(_private.parse_metadata(r.props)) do
			state[k] = v
		end
		for k, v in pairs(_private.parse_playback_props(r.props)) do
			state[k] = v
		end
		local flags = _private.parse_can_flags_partial(r.props)
		if state.track_id ~= nil then
			track_ids[source_id] = state.track_id
		end
		if next(state) ~= nil or flags ~= nil then
			registry.update(source_id, state, flags)
		end
	end

	local monitor_proc = Process({
		name = "media.mpris.monitor",
		cmd = {
			"dbus-monitor",
			"--session",
			"type='signal',"
				.. "interface='org.freedesktop.DBus.Properties',"
				.. "member='PropertiesChanged',"
				.. "path='/org/mpris/MediaPlayer2',"
				.. "arg0='org.mpris.MediaPlayer2.Player'",
		},
		retry_delay = 10,
		stdout = function(line)
			if line:match("^signal ") then
				-- Safety flush: dispatch any incomplete prior record then start fresh.
				dispatch_record()
				monitor_depth = 0
				monitor_arrays_closed = 0
				monitor_buffer = { line }
			else
				monitor_buffer[#monitor_buffer + 1] = line
				if line:match("%[%s*$") then
					monitor_depth = monitor_depth + 1
				elseif line:match("^%s*%]%s*$") then
					monitor_depth = monitor_depth - 1
					if monitor_depth == 0 then
						monitor_arrays_closed = monitor_arrays_closed + 1
						if monitor_arrays_closed == 2 then
							dispatch_record()
							monitor_depth = 0
							monitor_arrays_closed = 0
						end
					end
				end
			end
		end,
		exit = function()
			monitor_buffer = {}
			monitor_depth = 0
			monitor_arrays_closed = 0
		end,
	})

	-- NameOwnerChanged monitor for player appear/disappear.
	-- Pre-filtered by grep so only lines naming an MPRIS player reach Lua.
	local lifecycle_proc = Process({
		name = "media.mpris.lifecycle",
		cmd = {
			"sh",
			"-c",
			[[dbus-monitor --session "type='signal',member='NameOwnerChanged'" | grep --line-buffered '"org\.mpris\.MediaPlayer2\.']], -- luacheck: ignore
		},
		retry_delay = 10,
		stdout = function(line)
			local name = line:match('"(org%.mpris%.MediaPlayer2%.[^"]+)"')
			if name then
				discover_players()
				-- Check if this player has lost its owner (i.e., exited)
				if known_players[name] then
					dbus_send({
						print_reply = true,
						dest = "org.freedesktop.DBus",
						object_path = "/org/freedesktop/DBus",
						interface_member = "org.freedesktop.DBus.NameHasOwner",
						content = { "string:" .. name },
					}, function(stdout)
						if stdout and stdout:match("boolean false") then
							remove_player(name)
						end
					end)
				end
			end
		end,
	})

	return {
		name = "mpris",

		start = function(_, reg)
			registry = reg
			discover_players()
			monitor_proc:start()
			lifecycle_proc:start()
		end,

		stop = function(_)
			monitor_proc:stop()
			lifecycle_proc:stop()
		end,
	}
end

return setmetatable({}, {
	__call = function(_)
		return create_backend()
	end,
	__index = mpris,
})
