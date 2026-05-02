local awful = require("awful")
local Process = require("continuity.util.process")

local Pulse = {}

-- ----------------------------------------------------------------------------
-- Derive utilities
-- ----------------------------------------------------------------------------

---@param port_name string?
---@return string?
local function derive_port_type(port_name)
	if not port_name then
		return nil
	end
	local lower = port_name:lower()
	if lower:find("headset-mic", 1, true) then
		return "headset-mic"
	end
	if lower:find("headset", 1, true) then
		return "headset"
	end
	if lower:find("headphones", 1, true) then
		return "headphones"
	end
	if lower:find("speaker", 1, true) then
		return "speaker"
	end
	if lower:find("hdmi", 1, true) then
		return "hdmi"
	end
	if lower:find("mic", 1, true) then
		return "mic"
	end
	return nil
end

---@param device_name string?
---@return string?
local function derive_connection(device_name)
	if not device_name then
		return nil
	end
	if device_name:match("^bluez_") then
		return "bluetooth"
	end
	if device_name:find("bluez", 1, true) then
		return nil
	end
	if device_name:find("hdmi", 1, true) then
		return "hdmi"
	end
	if device_name:find("usb", 1, true) then
		return "usb"
	end
	if device_name:find("analog", 1, true) then
		return "analog"
	end
	return nil
end

-- ----------------------------------------------------------------------------
-- Parse volume/mute
-- ----------------------------------------------------------------------------

--- Parses combined stdout of:
---   pactl get-sink-volume ID; pactl get-sink-mute ID
--- Returns level (0–100) and muted, or nil, nil on parse failure.
---@param stdout string
---@return integer?, boolean?
local function parse_volume_mute(stdout)
	local level = tonumber(stdout:match("/%s+(%d+)%%"))
	local mute_str = stdout:match("Mute: (%a+)")
	if not level or not mute_str then
		return nil, nil
	end
	return level, mute_str == "yes"
end

-- ----------------------------------------------------------------------------
-- Parse poll list output
-- ----------------------------------------------------------------------------

--- Finds the block in `list` whose content contains `device_name`.
--- Blocks start at unindented "Sink #N" / "Source #N" lines.
--- Returns the block content (tab-indented lines) as a string, or nil.
---@param list string
---@param device_name string
---@return string?
local function find_device_block(list, device_name)
	local current_lines = {}
	local in_block = false

	local function check()
		if not in_block then
			return nil
		end
		local block = table.concat(current_lines, "\n")
		if block:find(device_name, 1, true) then
			return block
		end
		return nil
	end

	for line in (list .. "\n"):gmatch("([^\n]*)\n") do
		if line:match("^%u%l+ #%d+") then
			local found = check()
			if found then
				return found
			end
			in_block = true
			current_lines = {}
		elseif in_block then
			current_lines[#current_lines + 1] = line
		end
	end
	return check()
end

--- Parses the combined output of:
---   pactl get-default-sink; echo "---"; pactl list sinks
--- (or the source equivalent). `id` is set as the `id` field of the returned state.
---@param stdout string
---@return AudioState|nil
local function parse_list(stdout)
	local default_name = stdout:match("^([^\n]+)")
	if not default_name then
		return nil
	end
	local sentinel = stdout:find("\n---\n", 1, true)
	if not sentinel then
		return nil
	end
	local list = stdout:sub(sentinel + 5) -- skip past "\n---\n"

	local block = find_device_block(list, default_name)
	if not block then
		return nil
	end

	local level = tonumber(block:match("/%s+(%d+)%%"))
	local muted = block:match("Mute: (%a+)") == "yes"
	local port = block:match("\tActive Port: ([^\n]+)")
	local device_name = block:match("\tName: ([^\n]+)")

	return {
		level = level or 0,
		muted = muted or false,
		port = port,
		port_type = port and derive_port_type(port) or nil,
		connection = device_name and derive_connection(device_name) or nil,
	}
end

-- ----------------------------------------------------------------------------
-- Parse sink inputs
-- ----------------------------------------------------------------------------

--- Extracts the tab-indented block for Sink Input #id from full list output.
---@param stdout string  Output of: pactl list sink-inputs
---@param id     string  pactl sink-input index as string e.g. "263"
---@return string?
local function find_sink_input_block(stdout, id)
	local header = "Sink Input #" .. id .. "\n"
	local _, header_end = stdout:find(header, 1, true)
	if not header_end then
		return nil
	end
	local block_start = header_end + 1
	local block_end = stdout:find("\n%S", block_start)
	if block_end then
		return stdout:sub(block_start, block_end - 1)
	end
	return stdout:sub(block_start)
end

--- Parses a single sink-input block into a state and metadata table.
---@param id     string  pactl sink-input index as string e.g. "263"
---@param block  string  Tab-indented lines from find_sink_input_block
---@return SinkInputState, SinkInputMeta
local function parse_sink_input_block(id, block) -- luacheck: ignore 212
	local level = tonumber(block:match("/%s+(%d+)%%"))
	local muted = block:match("\tMute: (%a+)") == "yes"
	local sink = tonumber(block:match("\tSink: (%d+)"))
	local name = block:match('\tmedia%.name = "([^"]+)"')
	local app_name = block:match('\tapplication%.name = "([^"]+)"')
	local icon_name = block:match('\tapplication%.icon_name = "([^"]+)"')
	return {
		level = level or 0,
		muted = muted,
		sink = sink,
		name = name,
	}, {
		app_name = app_name,
		icon_name = icon_name,
	}
end

-- ----------------------------------------------------------------------------
-- Backend
-- ----------------------------------------------------------------------------

local SINK_ID = "@DEFAULT_SINK@"
local SOURCE_ID = "@DEFAULT_SOURCE@"

local SINK_POLL_CMD = { "sh", "-c", [[pactl get-default-sink; echo "---"; pactl list sinks]] }
local SOURCE_POLL_CMD = { "sh", "-c", [[pactl get-default-source; echo "---"; pactl list sources]] }

local SINK_QUERY_CMD = {
	"sh",
	"-c",
	[[pactl get-sink-volume @DEFAULT_SINK@; pactl get-sink-mute @DEFAULT_SINK@]],
}
local SOURCE_QUERY_CMD = {
	"sh",
	"-c",
	[[pactl get-source-volume @DEFAULT_SOURCE@; pactl get-source-mute @DEFAULT_SOURCE@]],
}
local QUERY_CMD = { [SINK_ID] = SINK_QUERY_CMD, [SOURCE_ID] = SOURCE_QUERY_CMD }
local SET_VOLUME = { [SINK_ID] = "set-sink-volume", [SOURCE_ID] = "set-source-volume" }
local SET_MUTE = { [SINK_ID] = "set-sink-mute", [SOURCE_ID] = "set-source-mute" }
local ENTITY = { [SINK_ID] = "sink", [SOURCE_ID] = "source" }

---@param opts? table  Reserved for future use.
---@return AudioBackend
local function create(_) -- luacheck: ignore
	local on_sink = nil
	local on_source = nil
	local pending = { sink = 0, source = 0 }
	local input_handles = nil
	local pending_inputs = {}

	local function poll_inputs()
		awful.spawn.easy_async({ "sh", "-c", "pactl list sink-inputs" }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not input_handles then
				return
			end
			local pos = 1
			while true do
				local _, header_end, idx_str = stdout:find("Sink Input #(%d+)\n", pos)
				if not header_end then
					break
				end
				local block_start = header_end + 1
				local block_end = stdout:find("\n%S", block_start)
				local block = block_end and stdout:sub(block_start, block_end - 1) or stdout:sub(block_start)
				local s, meta = parse_sink_input_block(idx_str, block)
				input_handles.add(idx_str, s, meta)
				pos = block_end or (#stdout + 1)
			end
		end)
	end

	local function poll_sink()
		awful.spawn.easy_async(SINK_POLL_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not on_sink then
				return
			end
			local state = parse_list(stdout)
			if state then
				on_sink(SINK_ID, state)
			end
		end)
	end

	local function poll_source()
		awful.spawn.easy_async(SOURCE_POLL_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not on_source then
				return
			end
			local state = parse_list(stdout)
			if state then
				on_source(SOURCE_ID, state)
			end
		end)
	end

	local proc = Process({
		name = "audio.pulse.subscribe",
		cmd = {
			"sh",
			"-c",
			[[pactl subscribe | grep --line-buffered -E "(Event 'change'|Event '(new|remove)' on sink-input)"]],
		},
		stdout = function(line)
			local entity = line:match("on ([%a%-]+) #")
			if entity == "sink" then
				if pending.sink > 0 then
					pending.sink = pending.sink - 1
				elseif on_sink then
					poll_sink()
				end
			elseif entity == "source" then
				if pending.source > 0 then
					pending.source = pending.source - 1
				elseif on_source then
					poll_source()
				end
			elseif entity == "server" then
				if on_sink then
					poll_sink()
				end
				if on_source then
					poll_source()
				end
			elseif entity == "sink-input" then
				if input_handles then
					local idx_str = line:match("#(%d+)")
					local event_type = line:match("Event '(%a+)'")
					if event_type == "remove" and idx_str then
						pending_inputs[idx_str] = nil
						input_handles.remove(idx_str)
					elseif event_type == "new" and idx_str then
						awful.spawn.easy_async(
							{ "sh", "-c", "pactl list sink-inputs" },
							function(stdout, _, _, exitcode)
								if exitcode ~= 0 or not input_handles then
									return
								end
								local block = find_sink_input_block(stdout, idx_str)
								if block then
									local s, meta = parse_sink_input_block(idx_str, block)
									input_handles.add(idx_str, s, meta)
								end
							end
						)
					elseif event_type == "change" and idx_str then
						if pending_inputs[idx_str] and pending_inputs[idx_str] > 0 then
							pending_inputs[idx_str] = pending_inputs[idx_str] - 1
						else
							awful.spawn.easy_async(
								{ "sh", "-c", "pactl list sink-inputs" },
								function(stdout, _, _, exitcode)
									if exitcode ~= 0 or not input_handles then
										return
									end
									local block = find_sink_input_block(stdout, idx_str)
									if block then
										local s = parse_sink_input_block(idx_str, block)
										input_handles.update(idx_str, s)
									end
								end
							)
						end
					end
				end
			end
		end,
	})

	local backend = {}

	---@param callbacks AudioBackendOpts?
	function backend:start(callbacks) -- luacheck: ignore self
		callbacks = callbacks or {}
		on_sink = callbacks.on_sink
		on_source = callbacks.on_source
		input_handles = callbacks.inputs or nil
		if on_sink then
			poll_sink()
		end
		if on_source then
			poll_source()
		end
		if input_handles then
			poll_inputs()
		end
		proc:start()
	end

	function backend:stop() -- luacheck: ignore self
		proc:stop()
		on_sink = nil
		on_source = nil
		input_handles = nil
		pending_inputs = {}
		pending.sink = 0
		pending.source = 0
	end

	local function after_set(id, cb)
		awful.spawn.easy_async(QUERY_CMD[id], function(stdout, _, _, exitcode)
			if exitcode ~= 0 then
				return
			end
			local level, muted = parse_volume_mute(stdout)
			if level ~= nil and cb then
				cb(level, muted)
			end
		end)
	end

	function backend:adjust_perc(id, delta, cb) -- luacheck: ignore self
		local ent = ENTITY[id]
		pending[ent] = pending[ent] + 1
		local sign = delta >= 0 and "+" or ""
		awful.spawn.easy_async(
			{ "pactl", SET_VOLUME[id], id, sign .. tostring(delta) .. "%" },
			function(_, _, _, exitcode)
				if exitcode ~= 0 then
					if pending[ent] > 0 then
						pending[ent] = pending[ent] - 1
					end
					return
				end
				after_set(id, cb)
			end
		)
	end

	function backend:set_perc(id, value, cb) -- luacheck: ignore self
		local ent = ENTITY[id]
		pending[ent] = pending[ent] + 1
		awful.spawn.easy_async(
			{ "pactl", SET_VOLUME[id], id, tostring(math.floor(value)) .. "%" },
			function(_, _, _, exitcode)
				if exitcode ~= 0 then
					if pending[ent] > 0 then
						pending[ent] = pending[ent] - 1
					end
					return
				end
				after_set(id, cb)
			end
		)
	end

	function backend:toggle(id, cb) -- luacheck: ignore self
		local ent = ENTITY[id]
		pending[ent] = pending[ent] + 1
		awful.spawn.easy_async({ "pactl", SET_MUTE[id], id, "toggle" }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				if pending[ent] > 0 then
					pending[ent] = pending[ent] - 1
				end
				return
			end
			after_set(id, cb)
		end)
	end

	function backend:mute(id, cb) -- luacheck: ignore self
		local ent = ENTITY[id]
		pending[ent] = pending[ent] + 1
		awful.spawn.easy_async({ "pactl", SET_MUTE[id], id, "1" }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				if pending[ent] > 0 then
					pending[ent] = pending[ent] - 1
				end
				return
			end
			after_set(id, cb)
		end)
	end

	function backend:unmute(id, cb) -- luacheck: ignore self
		local ent = ENTITY[id]
		pending[ent] = pending[ent] + 1
		awful.spawn.easy_async({ "pactl", SET_MUTE[id], id, "0" }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				if pending[ent] > 0 then
					pending[ent] = pending[ent] - 1
				end
				return
			end
			after_set(id, cb)
		end)
	end

	local function after_set_input(id, cb)
		awful.spawn.easy_async({ "sh", "-c", "pactl list sink-inputs" }, function(stdout, _, _, exitcode)
			if exitcode ~= 0 then
				return
			end
			local block = find_sink_input_block(stdout, id)
			if block and cb then
				local s = parse_sink_input_block(id, block)
				cb(s.level, s.muted)
			end
		end)
	end

	function backend:adjust_input_perc(id, delta, cb) -- luacheck: ignore self
		pending_inputs[id] = (pending_inputs[id] or 0) + 1
		local sign = delta >= 0 and "+" or ""
		awful.spawn.easy_async(
			{ "pactl", "set-sink-input-volume", id, sign .. tostring(delta) .. "%" },
			function(_, _, _, exitcode)
				if exitcode ~= 0 then
					if pending_inputs[id] and pending_inputs[id] > 0 then
						pending_inputs[id] = pending_inputs[id] - 1
					end
					return
				end
				after_set_input(id, cb)
			end
		)
	end

	function backend:set_input_perc(id, value, cb) -- luacheck: ignore self
		pending_inputs[id] = (pending_inputs[id] or 0) + 1
		awful.spawn.easy_async(
			{ "pactl", "set-sink-input-volume", id, tostring(math.floor(value)) .. "%" },
			function(_, _, _, exitcode)
				if exitcode ~= 0 then
					if pending_inputs[id] and pending_inputs[id] > 0 then
						pending_inputs[id] = pending_inputs[id] - 1
					end
					return
				end
				after_set_input(id, cb)
			end
		)
	end

	function backend:toggle_input(id, cb) -- luacheck: ignore self
		pending_inputs[id] = (pending_inputs[id] or 0) + 1
		awful.spawn.easy_async({ "pactl", "set-sink-input-mute", id, "toggle" }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				if pending_inputs[id] and pending_inputs[id] > 0 then
					pending_inputs[id] = pending_inputs[id] - 1
				end
				return
			end
			after_set_input(id, cb)
		end)
	end

	return backend
end

Pulse._private = {
	derive_port_type = derive_port_type,
	derive_connection = derive_connection,
	parse_volume_mute = parse_volume_mute,
	parse_list = parse_list,
	find_sink_input_block = find_sink_input_block,
	parse_sink_input_block = parse_sink_input_block,
}

return setmetatable(Pulse, {
	__call = function(_, opts)
		return create(opts)
	end,
})
