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

---@return AudioBackend
local function create()
	local on_sink = nil
	local on_source = nil
	local sink_handles = nil
	local source_handles = nil
	local pending = {}

	local function poll_sink()
		awful.spawn.easy_async({ "amixer", "sget", SINK_ID }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 then
				return
			end
			local level, muted = parse_channel(stdout)
			if level == nil then
				return
			end
			local state = { level = level, muted = muted, is_default = true }
			if on_sink then
				on_sink(SINK_ID, state, { name = SINK_ID, description = SINK_ID })
			end
			if sink_handles then
				sink_handles.update(SINK_ID, state)
			end
		end)
	end

	local function poll_source()
		awful.spawn.easy_async({ "amixer", "sget", SOURCE_ID }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 then
				return
			end
			local level, muted = parse_channel(stdout)
			if level == nil then
				return
			end
			local state = { level = level, muted = muted, is_default = true }
			if on_source then
				on_source(SOURCE_ID, state, { name = SOURCE_ID, description = SOURCE_ID })
			end
			if source_handles then
				source_handles.update(SOURCE_ID, state)
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

	local function after_set(idx, stdout, exitcode, cb)
		if exitcode ~= 0 then
			if pending[idx] and pending[idx] > 0 then
				pending[idx] = pending[idx] - 1
			end
			return
		end
		local level, muted = parse_channel(stdout)
		if level ~= nil and cb then
			cb(level, muted)
		end
	end

	local alsa_api = {
		adjust_perc = function(idx, delta, cb)
			pending[idx] = (pending[idx] or 0) + 1
			local cmd
			if delta >= 0 then
				cmd = { "amixer", "set", idx, tostring(delta) .. "%+", "on" }
			else
				cmd = { "amixer", "set", idx, tostring(-delta) .. "%-" }
			end
			awful.spawn.easy_async(cmd, function(stdout, _, _, exitcode)
				after_set(idx, stdout, exitcode, cb)
			end)
		end,
		set_perc = function(idx, value, cb)
			pending[idx] = (pending[idx] or 0) + 1
			awful.spawn.easy_async(
				{ "amixer", "set", idx, tostring(math.floor(value)) .. "%" },
				function(stdout, _, _, exitcode)
					after_set(idx, stdout, exitcode, cb)
				end
			)
		end,
		toggle = function(idx, cb)
			pending[idx] = (pending[idx] or 0) + 1
			awful.spawn.easy_async({ "amixer", "set", idx, "toggle" }, function(stdout, _, _, exitcode)
				after_set(idx, stdout, exitcode, cb)
			end)
		end,
		mute = function(idx, cb)
			pending[idx] = (pending[idx] or 0) + 1
			awful.spawn.easy_async({ "amixer", "set", idx, "off" }, function(stdout, _, _, exitcode)
				after_set(idx, stdout, exitcode, cb)
			end)
		end,
		unmute = function(idx, cb)
			pending[idx] = (pending[idx] or 0) + 1
			awful.spawn.easy_async({ "amixer", "set", idx, "on" }, function(stdout, _, _, exitcode)
				after_set(idx, stdout, exitcode, cb)
			end)
		end,
		set_default = function(_, cb)
			if cb then
				cb()
			end
		end,
		set_port = function() end,
	}

	local backend = {}

	backend.api = {
		sink = alsa_api,
		source = alsa_api,
		sink_input = {
			adjust_perc = function() end,
			set_perc = function() end,
			toggle = function() end,
			move = function() end,
		},
	}

	---@param callbacks AudioBackendOpts
	function backend:start(callbacks) -- luacheck: ignore self
		callbacks = callbacks or {}
		on_sink = callbacks.on_sink
		on_source = callbacks.on_source
		sink_handles = callbacks.sinks or nil
		source_handles = callbacks.sources or nil
		if sink_handles then
			sink_handles.add(
				SINK_ID,
				{ level = 0, muted = false, is_default = true },
				{ name = SINK_ID, description = SINK_ID }
			)
		end
		if source_handles then
			source_handles.add(
				SOURCE_ID,
				{ level = 0, muted = false, is_default = true },
				{ name = SOURCE_ID, description = SOURCE_ID }
			)
		end
		proc:start()
	end

	function backend:stop() -- luacheck: ignore self
		proc:stop()
		on_sink = nil
		on_source = nil
		sink_handles = nil
		source_handles = nil
		pending = {}
	end

	return backend
end

Alsa._private = {
	parse_channel = parse_channel,
}

return setmetatable(Alsa, {
	__call = function(_)
		return create()
	end,
})
