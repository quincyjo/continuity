local awful = require("awful")
local Process = require("continuity.util.process")

local Alsa = {}

-- ----------------------------------------------------------------------------
-- Parse
-- ----------------------------------------------------------------------------

---@param stdout string
---@return integer?, boolean?
local function parse_channel(stdout)
	local level = tonumber(stdout:match("%[(%d+)%%%]"))
	local status = stdout:match("%[(o[nf]+)%]")
	if not level or not status then
		return nil, nil
	end
	return level, status == "off"
end

-- ----------------------------------------------------------------------------
-- Backend
-- ----------------------------------------------------------------------------

local SINK_ID = "Master"
local SOURCE_ID = "Capture"

local POLL_CMD = {
	[SINK_ID] = { "amixer", "sget", "Master" },
	[SOURCE_ID] = { "amixer", "sget", "Capture" },
}
local TOGGLE_CMD = {
	[SINK_ID] = { "amixer", "set", "Master", "toggle" },
	[SOURCE_ID] = { "amixer", "set", "Capture", "toggle" },
}
local MUTE_CMD = {
	[SINK_ID] = { "amixer", "set", "Master", "off" },
	[SOURCE_ID] = { "amixer", "set", "Capture", "off" },
}
local UNMUTE_CMD = {
	[SINK_ID] = { "amixer", "set", "Master", "on" },
	[SOURCE_ID] = { "amixer", "set", "Capture", "on" },
}

---@param opts? table  Reserved for future use.
---@return AudioBackend
local function create(_) -- luacheck: ignore
	local on_sink = nil
	local on_source = nil
	local pending = { [SINK_ID] = 0, [SOURCE_ID] = 0 }

	local function poll_sink()
		awful.spawn.easy_async(POLL_CMD[SINK_ID], function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not on_sink then
				return
			end
			local level, muted = parse_channel(stdout)
			if level ~= nil then
				on_sink(SINK_ID, { level = level, muted = muted })
			end
		end)
	end

	local function poll_source()
		awful.spawn.easy_async(POLL_CMD[SOURCE_ID], function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not on_source then
				return
			end
			local level, muted = parse_channel(stdout)
			if level ~= nil then
				on_source(SOURCE_ID, { level = level, muted = muted })
			end
		end)
	end

	local proc = Process({
		name = "audio.alsa.sevents",
		cmd = { "amixer", "sevents" },
		stdout = function(line)
			local channel = line:match("event value: '([^']+)'")
			if not channel then
				return
			end
			if pending[channel] and pending[channel] > 0 then
				pending[channel] = pending[channel] - 1
			elseif channel == SINK_ID and on_sink then
				poll_sink()
			elseif channel == SOURCE_ID and on_source then
				poll_source()
			end
		end,
	})

	local backend = {}

	---@param callbacks AudioBackendOpts
	function backend:start(callbacks) -- luacheck: ignore self
		callbacks = callbacks or {}
		on_sink = callbacks.on_sink
		on_source = callbacks.on_source
		proc:start()
	end

	function backend:stop() -- luacheck: ignore self
		proc:stop()
		on_sink = nil
		on_source = nil
		pending[SINK_ID] = 0
		pending[SOURCE_ID] = 0
	end

	local function after_set(id, stdout, exitcode, cb)
		if exitcode ~= 0 then
			if pending[id] > 0 then
				pending[id] = pending[id] - 1
			end
			return
		end
		local level, muted = parse_channel(stdout)
		if level ~= nil and cb then
			cb(level, muted)
		end
	end

	function backend:adjust_perc(id, delta, cb) -- luacheck: ignore self
		pending[id] = pending[id] + 1
		local cmd
		if delta >= 0 then
			cmd = { "amixer", "set", id, tostring(delta) .. "%+", "on" }
		else
			cmd = { "amixer", "set", id, tostring(-delta) .. "%-" }
		end
		awful.spawn.easy_async(cmd, function(stdout, _, _, exitcode)
			after_set(id, stdout, exitcode, cb)
		end)
	end

	function backend:set_perc(id, value, cb) -- luacheck: ignore self
		pending[id] = pending[id] + 1
		local cmd = { "amixer", "set", id, tostring(math.floor(value)) .. "%" }
		awful.spawn.easy_async(cmd, function(stdout, _, _, exitcode)
			after_set(id, stdout, exitcode, cb)
		end)
	end

	function backend:toggle(id, cb) -- luacheck: ignore self
		pending[id] = pending[id] + 1
		awful.spawn.easy_async(TOGGLE_CMD[id], function(stdout, _, _, exitcode)
			after_set(id, stdout, exitcode, cb)
		end)
	end

	function backend:mute(id, cb) -- luacheck: ignore self
		pending[id] = pending[id] + 1
		awful.spawn.easy_async(MUTE_CMD[id], function(stdout, _, _, exitcode)
			after_set(id, stdout, exitcode, cb)
		end)
	end

	function backend:unmute(id, cb) -- luacheck: ignore self
		pending[id] = pending[id] + 1
		awful.spawn.easy_async(UNMUTE_CMD[id], function(stdout, _, _, exitcode)
			after_set(id, stdout, exitcode, cb)
		end)
	end

	return backend
end

Alsa._private = {
	parse_channel = parse_channel,
}

return setmetatable(Alsa, {
	__call = function(_, opts)
		return create(opts)
	end,
})
