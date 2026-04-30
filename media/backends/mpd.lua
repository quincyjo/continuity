-- MPD backend.
-- Maintains a persistent connection using the MPD idle protocol for push updates.
-- One configured host:port = one source.

local awful = require("awful")
local gears = require("gears")
local Process = require("continuity.util.process")

---@class MpdOpts
---@field host?      string   Defaults to "127.0.0.1"
---@field port?      integer  Defaults to 6600
---@field password?  string
---@field label?     string   Human-readable source name. Defaults to "mpd".
---@field music_dir? string   Base directory for local cover art search.

local mpd = {}

local STATUS_MAP = { play = "playing", pause = "paused", stop = "stopped" }

--- Parse a raw MPD protocol response into a partial MediaState.
--- Only fields present in the response are populated; absent fields are left nil
--- so that registry.update() partial-merge semantics are preserved.
--- art_uri is NOT set here — it is resolved asynchronously in fetch_state.
---@param raw string
---@return MediaState
function mpd._parse_response(raw)
	local state = {}
	local rep, single
	-- Track whether repeat/single appeared; only set state.loop if they did.
	-- A metadata-only partial response must not overwrite an existing loop value.
	local has_rep, has_single = false, false

	for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
		local k, v = line:match("^([%w]+):%s*(.-)%s*$")
		if k and v then
			if k == "state" then
				state.status = STATUS_MAP[v]
			elseif k == "file" then
				state.uri = v
			elseif k == "Artist" then
				state.artist = v
			elseif k == "Title" then
				state.title = v
			elseif k == "Album" then
				state.album = v
			elseif k == "Genre" then
				state.genre = v
			elseif k == "Date" then
				state.date = v
			elseif k == "Track" then
				-- MPD may return "5/12"; extract only the leading integer.
				state.track_number = tonumber(v:match("^%d+"))
			elseif k == "Time" then
				state.duration = tonumber(v)
			elseif k == "elapsed" then
				state.position = tonumber(v)
			elseif k == "song" then
				state.queue_position = tonumber(v)
			elseif k == "playlistlength" then
				state.queue_length = tonumber(v)
			elseif k == "volume" then
				state.volume = tonumber(v)
			elseif k == "random" then
				state.shuffle = v == "1"
			elseif k == "consume" then
				state.consume = v == "1"
			elseif k == "repeat" then
				rep = tonumber(v) or 0
				has_rep = true
			elseif k == "single" then
				single = tonumber(v) or 0
				has_single = true
			end
		end
	end

	-- Only populate loop when at least one flag appeared in this response.
	if has_rep or has_single then
		rep = rep or 0
		single = single or 0
		if rep == 1 and single == 0 then
			state.loop = "playlist"
		elseif single == 1 then
			state.loop = "track"
		else
			state.loop = "none"
		end
	end

	return state
end

--- Returns true if the file path is a local file (not a URI scheme).
---@param uri string
---@return boolean
local function is_local_file(uri)
	return uri ~= nil and not uri:match("^%a+://") and not uri:match("^%a+:%a+:")
end

--- Async find for local album art in the song's directory.
---@param music_dir string
---@param file_path string
---@param cb fun(path: string|nil)
local function find_local_art(music_dir, file_path, cb)
	local dir = file_path:match("^(.+)/[^/]+$") or ""
	local full_dir = music_dir .. "/" .. dir
	local cmd = string.format("find %q -maxdepth 1 -type f | grep -iE '\\.(jpg|jpeg|png|gif)$' | head -1", full_dir)
	awful.spawn.easy_async({ "sh", "-c", cmd }, function(stdout)
		local path = stdout:gsub("%s+$", "")
		cb(#path > 0 and path or nil)
	end)
end

--- Returns a Backend instance.
---@param opts? MpdOpts
---@return Backend
local function create_backend(opts)
	opts = opts or {}
	local host = opts.host or "127.0.0.1"
	local port = opts.port or 6600
	local password = opts.password
	local label = opts.label or "mpd"
	local music_dir = opts.music_dir or (os.getenv("HOME") .. "/Music")

	local source_id = string.format("mpd:%s:%d", host, port)
	---@type SourceRegistrar
	local registry
	local connected = false
	---@type table|nil
	local position_timer = nil

	local function fetch_state()
		local parts = {}
		if password then
			parts[#parts + 1] = string.format("password %s\n", password)
		end
		parts[#parts + 1] = "status\ncurrentsong\nclose\n"
		local payload = table.concat(parts)
		local cmd = string.format("printf %q | nc -q1 %s %d 2>/dev/null", payload, host, port)
		awful.spawn.easy_async({ "sh", "-c", cmd }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or stdout == "" then
				gears.debug.print_warning(string.format("media.mpd: fetch failed for %s:%d", host, port))
				return
			end
			local state = mpd._parse_response(stdout)
			if state.uri and is_local_file(state.uri) then
				find_local_art(music_dir, state.uri, function(art_path)
					state.art_uri = art_path
					registry.update(source_id, state)
				end)
			else
				registry.update(source_id, state)
			end
		end)
	end

	local connect_cmd = string.format(
		"printf %q | nc %s %d 2>/dev/null",
		table.concat(password and { string.format("password %s\n", password), "idle player mixer options\n" }
			or { "idle player mixer options\n" }),
		host,
		port
	)

	local proc = Process({
		name = string.format("media.mpd:%s:%d", host, port),
		cmd = { "sh", "-c", connect_cmd },
		retry_delay = 10,
		stdout = function(line)
			if line:match("^OK MPD") then
				if not connected then
					connected = true
					fetch_state()
				end
			elseif line:match("^changed:") then
				fetch_state()
			end
		end,
		exit = function()
			connected = false
		end,
	})

	---@param cb fun(pos: number)
	---@return fun()
	local function subscribe_position(cb)
		if position_timer then
			return function()
				if position_timer then
					position_timer:stop()
					position_timer = nil
				end
			end
		end
		position_timer = gears.timer({
			timeout = 1,
			autostart = true,
			callback = function()
				local cmd = string.format("printf %q | nc -q1 %s %d 2>/dev/null", "status\nclose\n", host, port)
				awful.spawn.easy_async({ "sh", "-c", cmd }, function(stdout, _, _, exitcode)
					if exitcode ~= 0 or stdout == "" then
						return
					end
					local pos = mpd._parse_response(stdout).position
					if pos then
						cb(pos)
					end
				end)
			end,
		})
		return function()
			if position_timer then
				position_timer:stop()
				position_timer = nil
			end
		end
	end

	---@param cb fun(pos: number|nil)
	local function get_position(cb)
		local cmd = string.format("printf %q | nc -q1 %s %d 2>/dev/null", "status\nclose\n", host, port)
		awful.spawn.easy_async({ "sh", "-c", cmd }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or stdout == "" then
				cb(nil)
				return
			end
			cb(mpd._parse_response(stdout).position)
		end)
	end

	local function send(payload, cb)
		local cmd = string.format("printf %q | nc -q1 %s %d 2>/dev/null", payload, host, port)
		awful.spawn.easy_async({ "sh", "-c", cmd }, cb or function() end)
	end

	local function simple(payload)
		send(payload)
	end

	return {
		name = label,

		start = function(_, reg)
			registry = reg
			local function push_position(pos)
				registry.update(source_id, { position = pos })
			end
			registry.add(source_id, label, {}, {
				position = {
					subscribe = function(_, cb)
						return subscribe_position(cb)
					end,
					get = function(_, cb)
						get_position(cb)
					end,
				},
				playback = {
					play = function(_)
						simple("play\nclose\n")
					end,
					pause = function(_)
						simple("pause 1\nclose\n")
					end,
					play_pause = function(_)
						simple("pause\nclose\n")
					end,
					stop = function(_)
						simple("stop\nclose\n")
					end,
					next = function(_)
						simple("next\nclose\n")
					end,
					previous = function(_)
						simple("previous\nclose\n")
					end,
					seek = function(_, offset_seconds)
						local payload = string.format("seekcur %+.3f\nclose\n", offset_seconds)
						send(payload, function()
							get_position(push_position)
						end)
					end,
					set_position = function(_, pos_seconds)
						local payload = string.format("seekcur %.3f\nclose\n", pos_seconds)
						send(payload, function()
							push_position(pos_seconds)
						end)
					end,
				},
				flags = {
					can_control = true,
					can_seek = true,
					can_go_next = true,
					can_go_previous = true,
					can_play = true,
					can_pause = true,
				},
			})
			proc:start()
		end,

		stop = function(_)
			proc:stop()
		end,
	}
end

return setmetatable({}, {
	__call = function(_, opts)
		return create_backend(opts)
	end,
	__index = mpd,
})
