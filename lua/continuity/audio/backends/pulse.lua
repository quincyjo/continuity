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

--- Finds the tab-indented block for device index `index_str` in a `pactl list` output.
--- `list` is the portion of output after the "---\n" sentinel (i.e. the raw list output).
---@param list string
---@param index_str string  e.g. "57"
---@return string?
local function find_device_block_by_index(list, index_str)
	local header = "#" .. index_str .. "\n"
	local _, header_end = list:find(header, 1, true)
	if not header_end then
		return nil
	end
	local block_start = header_end + 1
	local block_end = list:find("\n%S", block_start)
	if block_end then
		return list:sub(block_start, block_end - 1)
	end
	return list:sub(block_start)
end

--- Parses a single device block into state and metadata.
--- `default_name` is the device name of the current default (first line of combined output).
---@param block string
---@param default_name string
---@return { state: AudioState, meta: { name: string?, description: string? } }
local function parse_device_block(block, default_name)
	local name = block:match("\tName: ([^\n]+)")
	local description = block:match("\tDescription: ([^\n]+)")
	local level = tonumber(block:match("/%s+(%d+)%%"))
	local muted = block:match("\tMute: (%a+)") == "yes"
	local port = block:match("\tActive Port: ([^\n]+)")
	return {
		state = {
			level = level or 0,
			muted = muted or false,
			port = port,
			port_type = port and derive_port_type(port) or nil,
			connection = name and derive_connection(name) or nil,
			is_default = name == default_name,
		},
		meta = { name = name, description = description },
	}
end

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
-- Parse all devices
-- ----------------------------------------------------------------------------

--- Parses combined output of:
---   pactl get-default-sink; echo "---"; pactl list sinks
--- (or the source equivalent). Returns one entry per device.
---@param stdout string
---@return { id: string, state: AudioState, meta: { name: string?, description: string? } }[]
local function parse_all_devices(stdout)
	local default_name = stdout:match("^([^\n]+)")
	local sentinel = stdout:find("\n---\n", 1, true)
	if not default_name or not sentinel then
		return {}
	end
	local list = stdout:sub(sentinel + 5)

	local entries = {}
	local idx_str, block_start
	local pos = 1

	while true do
		local header_start, header_end, captured_idx = list:find("%u%l+ #(%d+)\n", pos)
		if not header_start then
			break
		end
		if idx_str then
			local parsed = parse_device_block(list:sub(block_start, header_start - 1), default_name)
			entries[#entries + 1] = { id = idx_str, state = parsed.state, meta = parsed.meta }
		end
		idx_str = captured_idx
		block_start = header_end + 1
		pos = header_end + 1
	end

	if idx_str then
		local parsed = parse_device_block(list:sub(block_start), default_name)
		entries[#entries + 1] = { id = idx_str, state = parsed.state, meta = parsed.meta }
	end

	return entries
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

local SINK_POLL_CMD = { "sh", "-c", [[pactl get-default-sink; echo "---"; pactl list sinks]] }
local SOURCE_POLL_CMD = { "sh", "-c", [[pactl get-default-source; echo "---"; pactl list sources]] }

---@param opts? table  Reserved for future use.
---@return AudioBackend
local function create(_) -- luacheck: ignore
	local on_sink = nil
	local on_source = nil
	local pending = { server = 0 }
	local input_handles = nil
	local sink_handles = nil
	local source_handles = nil
	local current_default_sink = nil
	local current_default_source = nil
	local current_default_sink_idx = nil
	local current_default_source_idx = nil
	local pending_sinks = {}
	local pending_sources = {}
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

	local function poll_sinks()
		awful.spawn.easy_async(SINK_POLL_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not sink_handles then
				return
			end
			local entries = parse_all_devices(stdout)
			local default_state = nil
			for _, entry in ipairs(entries) do
				sink_handles.add(entry.id, entry.state, entry.meta)
				if entry.state.is_default then
					current_default_sink = entry.meta.name
					current_default_sink_idx = entry.id
					default_state = entry.state
				end
			end
			if on_sink and default_state then
				on_sink(current_default_sink_idx, default_state)
			end
		end)
	end

	local function poll_sources()
		awful.spawn.easy_async(SOURCE_POLL_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not source_handles then
				return
			end
			local entries = parse_all_devices(stdout)
			local default_state = nil
			for _, entry in ipairs(entries) do
				source_handles.add(entry.id, entry.state, entry.meta)
				if entry.state.is_default then
					current_default_source = entry.meta.name
					current_default_source_idx = entry.id
					default_state = entry.state
				end
			end
			if on_source and default_state then
				on_source(current_default_source_idx, default_state)
			end
		end)
	end

	local proc = Process({
		name = "audio.pulse.subscribe",
		cmd = {
			"sh",
			"-c",
			[[pactl subscribe | grep --line-buffered -E "(Event 'change'|Event '(new|remove)' on (sink-input|sink|source))"]],
		},
		stdout = function(line)
			local entity = line:match("on ([%a%-]+) #")
			if entity == "sink" then
				local event_type = line:match("Event '(%a+)'")
				local idx_str = line:match("#(%d+)")
				if not idx_str then
					return
				end
				if event_type == "new" then
					if not sink_handles then
						return
					end
					awful.spawn.easy_async(SINK_POLL_CMD, function(stdout, _, _, exitcode)
						if exitcode ~= 0 or not sink_handles then
							return
						end
						local default_name = stdout:match("^([^\n]+)")
						local sentinel = stdout:find("\n---\n", 1, true)
						if not default_name or not sentinel then
							return
						end
						local block = find_device_block_by_index(stdout:sub(sentinel + 5), idx_str)
						if block then
							local parsed = parse_device_block(block, default_name)
							sink_handles.add(idx_str, parsed.state, parsed.meta)
						end
					end)
				elseif event_type == "change" then
					if sink_handles then
						if pending_sinks[idx_str] and pending_sinks[idx_str] > 0 then
							pending_sinks[idx_str] = pending_sinks[idx_str] - 1
							return
						end
						awful.spawn.easy_async(SINK_POLL_CMD, function(stdout, _, _, exitcode)
							if exitcode ~= 0 or not sink_handles then
								return
							end
							local default_name = stdout:match("^([^\n]+)")
							local sentinel = stdout:find("\n---\n", 1, true)
							if not default_name or not sentinel then
								return
							end
							local block = find_device_block_by_index(stdout:sub(sentinel + 5), idx_str)
							if block then
								local parsed = parse_device_block(block, default_name)
								sink_handles.update(idx_str, parsed.state)
								if parsed.state.is_default and on_sink then
									on_sink(current_default_sink_idx, parsed.state)
								end
							end
						end)
					end
				elseif event_type == "remove" then
					if sink_handles then
						sink_handles.remove(idx_str)
					end
				end
			elseif entity == "source" then
				local event_type = line:match("Event '(%a+)'")
				local idx_str = line:match("#(%d+)")
				if not idx_str then
					return
				end
				if event_type == "new" then
					if not source_handles then
						return
					end
					awful.spawn.easy_async(SOURCE_POLL_CMD, function(stdout, _, _, exitcode)
						if exitcode ~= 0 or not source_handles then
							return
						end
						local default_name = stdout:match("^([^\n]+)")
						local sentinel = stdout:find("\n---\n", 1, true)
						if not default_name or not sentinel then
							return
						end
						local block = find_device_block_by_index(stdout:sub(sentinel + 5), idx_str)
						if block then
							local parsed = parse_device_block(block, default_name)
							source_handles.add(idx_str, parsed.state, parsed.meta)
						end
					end)
				elseif event_type == "change" then
					if source_handles then
						if pending_sources[idx_str] and pending_sources[idx_str] > 0 then
							pending_sources[idx_str] = pending_sources[idx_str] - 1
							return
						end
						awful.spawn.easy_async(SOURCE_POLL_CMD, function(stdout, _, _, exitcode)
							if exitcode ~= 0 or not source_handles then
								return
							end
							local default_name = stdout:match("^([^\n]+)")
							local sentinel = stdout:find("\n---\n", 1, true)
							if not default_name or not sentinel then
								return
							end
							local block = find_device_block_by_index(stdout:sub(sentinel + 5), idx_str)
							if block then
								local parsed = parse_device_block(block, default_name)
								source_handles.update(idx_str, parsed.state)
								if parsed.state.is_default and on_source then
									on_source(current_default_source_idx, parsed.state)
								end
							end
						end)
					end
				elseif event_type == "remove" then
					if source_handles then
						source_handles.remove(idx_str)
					end
				end
			elseif entity == "server" then
				if pending.server > 0 then
					pending.server = pending.server - 1
					return
				end
				if sink_handles then
					awful.spawn.easy_async(SINK_POLL_CMD, function(stdout, _, _, exitcode)
						if exitcode ~= 0 then
							return
						end
						local new_default = stdout:match("^([^\n]+)")
						if new_default and new_default ~= current_default_sink then
							local entries = parse_all_devices(stdout)
							for _, entry in ipairs(entries) do
								if entry.meta.name == current_default_sink or entry.meta.name == new_default then
									sink_handles.update(entry.id, entry.state)
									if entry.state.is_default then
										current_default_sink_idx = entry.id
										if on_sink then
											on_sink(current_default_sink_idx, entry.state)
										end
									end
								end
							end
							current_default_sink = new_default
						end
					end)
				end
				if source_handles then
					awful.spawn.easy_async(SOURCE_POLL_CMD, function(stdout, _, _, exitcode)
						if exitcode ~= 0 then
							return
						end
						local new_default = stdout:match("^([^\n]+)")
						if new_default and new_default ~= current_default_source then
							local entries = parse_all_devices(stdout)
							for _, entry in ipairs(entries) do
								if entry.meta.name == current_default_source or entry.meta.name == new_default then
									source_handles.update(entry.id, entry.state)
									if entry.state.is_default then
										current_default_source_idx = entry.id
										if on_source then
											on_source(current_default_source_idx, entry.state)
										end
									end
								end
							end
							current_default_source = new_default
						end
					end)
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
		sink_handles = callbacks.sinks or nil
		source_handles = callbacks.sources or nil
		if sink_handles then
			poll_sinks()
		end
		if source_handles then
			poll_sources()
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
		sink_handles = nil
		source_handles = nil
		current_default_sink = nil
		current_default_source = nil
		current_default_sink_idx = nil
		current_default_source_idx = nil
		pending_sinks = {}
		pending_sources = {}
		pending_inputs = {}
		pending.server = 0
	end

	local function after_set_sink(idx, cb)
		awful.spawn.easy_async(
			{ "sh", "-c", "pactl get-sink-volume " .. idx .. "; pactl get-sink-mute " .. idx },
			function(stdout, _, _, exitcode)
				if exitcode ~= 0 then
					return
				end
				local level, muted = parse_volume_mute(stdout)
				if level ~= nil and cb then
					cb(level, muted)
				end
			end
		)
	end

	local function after_set_source(idx, cb)
		awful.spawn.easy_async(
			{ "sh", "-c", "pactl get-source-volume " .. idx .. "; pactl get-source-mute " .. idx },
			function(stdout, _, _, exitcode)
				if exitcode ~= 0 then
					return
				end
				local level, muted = parse_volume_mute(stdout)
				if level ~= nil and cb then
					cb(level, muted)
				end
			end
		)
	end

	local function make_device_api(cmd_volume, cmd_mute, pending_tbl, after_set_fn)
		return {
			adjust_perc = function(idx, delta, cb)
				pending_tbl[idx] = (pending_tbl[idx] or 0) + 1
				local sign = delta >= 0 and "+" or ""
				awful.spawn.easy_async(
					{ "pactl", cmd_volume, idx, sign .. tostring(delta) .. "%" },
					function(_, _, _, exitcode)
						if exitcode ~= 0 then
							if pending_tbl[idx] and pending_tbl[idx] > 0 then
								pending_tbl[idx] = pending_tbl[idx] - 1
							end
							return
						end
						after_set_fn(idx, cb)
					end
				)
			end,
			set_perc = function(idx, value, cb)
				pending_tbl[idx] = (pending_tbl[idx] or 0) + 1
				awful.spawn.easy_async(
					{ "pactl", cmd_volume, idx, tostring(math.floor(value)) .. "%" },
					function(_, _, _, exitcode)
						if exitcode ~= 0 then
							if pending_tbl[idx] and pending_tbl[idx] > 0 then
								pending_tbl[idx] = pending_tbl[idx] - 1
							end
							return
						end
						after_set_fn(idx, cb)
					end
				)
			end,
			toggle = function(idx, cb)
				pending_tbl[idx] = (pending_tbl[idx] or 0) + 1
				awful.spawn.easy_async({ "pactl", cmd_mute, idx, "toggle" }, function(_, _, _, exitcode)
					if exitcode ~= 0 then
						if pending_tbl[idx] and pending_tbl[idx] > 0 then
							pending_tbl[idx] = pending_tbl[idx] - 1
						end
						return
					end
					after_set_fn(idx, cb)
				end)
			end,
			mute = function(idx, cb)
				pending_tbl[idx] = (pending_tbl[idx] or 0) + 1
				awful.spawn.easy_async({ "pactl", cmd_mute, idx, "1" }, function(_, _, _, exitcode)
					if exitcode ~= 0 then
						if pending_tbl[idx] and pending_tbl[idx] > 0 then
							pending_tbl[idx] = pending_tbl[idx] - 1
						end
						return
					end
					after_set_fn(idx, cb)
				end)
			end,
			unmute = function(idx, cb)
				pending_tbl[idx] = (pending_tbl[idx] or 0) + 1
				awful.spawn.easy_async({ "pactl", cmd_mute, idx, "0" }, function(_, _, _, exitcode)
					if exitcode ~= 0 then
						if pending_tbl[idx] and pending_tbl[idx] > 0 then
							pending_tbl[idx] = pending_tbl[idx] - 1
						end
						return
					end
					after_set_fn(idx, cb)
				end)
			end,
		}
	end

	local sink_api = make_device_api("set-sink-volume", "set-sink-mute", pending_sinks, after_set_sink)
	local source_api = make_device_api("set-source-volume", "set-source-mute", pending_sources, after_set_source)

	sink_api.set_default = function(idx, cb)
		pending.server = pending.server + 1
		awful.spawn.easy_async({ "pactl", "set-default-sink", idx }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				pending.server = pending.server - 1
				return
			end
			if cb then
				cb()
			end
		end)
	end

	source_api.set_default = function(idx, cb)
		pending.server = pending.server + 1
		awful.spawn.easy_async({ "pactl", "set-default-source", idx }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				pending.server = pending.server - 1
				return
			end
			if cb then
				cb()
			end
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

	local sink_input_api = {
		adjust_perc = function(id, delta, cb)
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
		end,
		set_perc = function(id, value, cb)
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
		end,
		toggle = function(id, cb)
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
		end,
		move = function(input_id, sink_id, cb)
			awful.spawn.easy_async(
				{ "pactl", "move-sink-input", tostring(input_id), tostring(sink_id) },
				function(_, _, _, exitcode)
					if exitcode == 0 and cb then
						cb()
					end
				end
			)
		end,
	}

	backend.api = {
		sink = sink_api,
		source = source_api,
		sink_input = sink_input_api,
	}

	return backend
end

Pulse._private = {
	derive_port_type = derive_port_type,
	derive_connection = derive_connection,
	parse_volume_mute = parse_volume_mute,
	parse_list = parse_list,
	parse_all_devices = parse_all_devices,
	find_device_block_by_index = find_device_block_by_index,
	parse_device_block = parse_device_block,
	find_sink_input_block = find_sink_input_block,
	parse_sink_input_block = parse_sink_input_block,
}

return setmetatable(Pulse, {
	__call = function(_, opts)
		return create(opts)
	end,
})
