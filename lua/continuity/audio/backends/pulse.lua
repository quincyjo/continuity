local awful = require("awful")
local Process = require("continuity.util.process")
local json = require("continuity.util.json")
local app_icon = require("continuity.util.app_icon")

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
-- Parse ports
-- ----------------------------------------------------------------------------

---@param avail_str string  Raw availability string from pactl
---@return "available"|"not available"|"unknown"
local function normalize_availability(avail_str)
	if avail_str:match("^availability ") then
		return avail_str:sub(14)
	end
	return avail_str
end

--- Parses port lines from a device block (text format).
--- Returns nil if no port lines are found.
---@param block string
---@return AudioPort[]?
local function parse_ports_text(block)
	local ports = {}
	for line in block:gmatch("[^\n]+") do
		local name, desc, prio, avail_str =
			line:match("^\t\t([^:]+): ([^(]+)%(type: [^,]+, priority: (%d+), availability group: [^,]+, ([^)]+)%)")
		if name then
			ports[#ports + 1] = {
				name = name,
				description = desc:match("^%s*(.-)%s*$"),
				type = derive_port_type(name),
				priority = tonumber(prio),
				availability = normalize_availability(avail_str),
			}
		end
	end
	return #ports > 0 and ports or nil
end

--- Parses ports from a pactl JSON ports array.
--- Returns nil if array is nil, json.null, or empty.
---@param ports_arr table?
---@return AudioPort[]?
local function parse_ports_json(ports_arr)
	if not ports_arr or ports_arr == json.null then
		return nil
	end
	local ports = {}
	for _, p in ipairs(ports_arr) do
		ports[#ports + 1] = {
			name = p.name,
			description = p.description,
			type = derive_port_type(p.name),
			priority = p.priority,
			availability = normalize_availability(p.availability or "availability unknown"),
		}
	end
	return #ports > 0 and ports or nil
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
-- Parse poll list output (text format)
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
			ports = parse_ports_text(block),
			connection = name and derive_connection(name) or nil,
			is_default = name == default_name,
		},
		meta = { name = name, description = description },
	}
end

--- Parses combined output of:
---   pactl get-default-sink; echo "---"; pactl list sinks
--- (or the source equivalent). Returns one entry per device.
---@param stdout string
---@return { id: string, state: AudioState, meta: { name: string?, description: string? } }[]
local function parse_all_devices_text(stdout)
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

--- Parses a single device by index from combined stdout (text format).
---@param stdout string
---@param idx_str string
---@return { state: AudioState, meta: { name: string?, description: string? } }?
local function parse_device_by_index_text(stdout, idx_str)
	local default_name = stdout:match("^([^\n]+)")
	local sentinel = stdout:find("\n---\n", 1, true)
	if not default_name or not sentinel then
		return nil
	end
	local block = find_device_block_by_index(stdout:sub(sentinel + 5), idx_str)
	if not block then
		return nil
	end
	return parse_device_block(block, default_name)
end

-- ----------------------------------------------------------------------------
-- Parse sink inputs (text format)
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
---@param block  string  Tab-indented lines from find_sink_input_block
---@return SinkInputState, SinkInputMeta
local function parse_sink_input_block(block)
	local level = tonumber(block:match("/%s+(%d+)%%"))
	local muted = block:match("\tMute: (%a+)") == "yes"
	local corked = block:match("\tCorked: (%a+)") == "yes"
	local sink = tonumber(block:match("\tSink: (%d+)"))
	local name = block:match('\tmedia%.name = "([^"]+)"')
	local app_name = block:match('\tapplication%.name = "([^"]+)"')
	local icon_name = block:match('\tapplication%.icon_name = "([^"]+)"')
	local role = block:match('\tmedia%.role = "([^"]+)"')
	local binary = block:match('\tapplication%.process%.binary = "([^"]+)"')
	return {
		level = level or 0,
		muted = muted,
		corked = corked,
		sink = sink,
		name = name,
	}, {
		app_name = app_name,
		icon_name = icon_name,
		role = role,
		binary = binary,
	}
end

--- Parses all sink inputs from text list output.
---@param stdout string  Output of: pactl list sink-inputs
---@return { id: string, state: SinkInputState, meta: SinkInputMeta }[]
local function parse_all_sink_inputs_text(stdout)
	local entries = {}
	local pos = 1
	while true do
		local _, header_end, idx_str = stdout:find("Sink Input #(%d+)\n", pos)
		if not header_end then
			break
		end
		local block_start = header_end + 1
		local block_end = stdout:find("\n%S", block_start)
		local block = block_end and stdout:sub(block_start, block_end - 1) or stdout:sub(block_start)
		local s, meta = parse_sink_input_block(block)
		entries[#entries + 1] = { id = idx_str, state = s, meta = meta }
		pos = block_end or (#stdout + 1)
	end
	return entries
end

--- Parses a single sink input by id from text list output.
---@param stdout string
---@param id string
---@return SinkInputState?, SinkInputMeta?
local function parse_sink_input_by_index_text(stdout, id)
	local block = find_sink_input_block(stdout, id)
	if not block then
		return nil, nil
	end
	return parse_sink_input_block(block)
end

-- ----------------------------------------------------------------------------
-- Parse poll list output (JSON format)
-- ----------------------------------------------------------------------------

--- Extracts volume level (0-100) from a pactl JSON volume object.
---@param vol table?
---@return integer
local function volume_level_json(vol)
	if not vol then
		return 0
	end
	local _, ch = next(vol)
	if not ch then
		return 0
	end
	return tonumber(ch.value_percent:match("(%d+)%%")) or 0
end

---@param default_name string
---@param dev table
---@return { id: string, state: AudioState, meta: { name: string?, description: string? } }
local function audio_form_json(default_name, dev)
	local name = dev.name
	local port = dev.active_port and dev.active_port ~= json.null and dev.active_port or nil
	return {
		id = tostring(dev.index),
		state = {
			level = volume_level_json(dev.volume),
			muted = dev.mute == true,
			port = port,
			port_type = port and derive_port_type(port) or nil,
			ports = parse_ports_json(dev.ports),
			connection = name and derive_connection(name) or nil,
			is_default = name == default_name,
		},
		meta = { name = name, description = dev.description },
	}
end

--- Parses combined output of:
---   pactl get-default-sink; echo "---"; pactl --format=json list sinks
--- (or the source equivalent). Returns one entry per device.
---@param stdout string
---@return { id: string, state: AudioState, meta: { name: string?, description: string? } }[]
local function parse_all_devices_json(stdout)
	local default_name = stdout:match("^([^\n]+)")
	local sentinel = stdout:find("\n---\n", 1, true)
	if not default_name or not sentinel then
		return {}
	end
	local ok, devices = pcall(json.decode, stdout:sub(sentinel + 5))
	if not ok or type(devices) ~= "table" then
		return {}
	end
	local entries = {}
	for _, dev in ipairs(devices) do
		entries[#entries + 1] = audio_form_json(default_name, dev)
	end
	return entries
end

--- Parses a single device by index from combined stdout (JSON format).
---@param stdout string
---@param idx_str string
---@return { state: AudioState, meta: { name: string?, description: string? } }?
local function parse_device_by_index_json(stdout, idx_str)
	local default_name = stdout:match("^([^\n]+)")
	local sentinel = stdout:find("\n---\n", 1, true)
	if not default_name or not sentinel then
		return nil
	end
	local ok, devices = pcall(json.decode, stdout:sub(sentinel + 5))
	if not ok or type(devices) ~= "table" then
		return nil
	end
	local target = tonumber(idx_str)
	for _, dev in ipairs(devices) do
		if dev.index == target then
			return audio_form_json(default_name, dev)
		end
	end
	return nil
end

-- ----------------------------------------------------------------------------
-- Parse sink inputs (JSON format)
-- ----------------------------------------------------------------------------

---@param inp table The JSON object for a single sink input>
---@return { id: string, state: SinkInputState, meta: SinkInputMeta }
local function input_from_json(inp)
	local props = inp.properties ~= json.null and inp.properties or {}
	local function prop(key)
		local v = props[key]
		return (v ~= nil and v ~= json.null) and v or nil
	end
	return {
		id = tostring(inp.index),
		state = {
			level = volume_level_json(inp.volume),
			muted = inp.mute == true,
			corked = inp.corked == true,
			sink = inp.sink,
			name = prop("media.name"),
		},
		meta = {
			app_name = prop("application.name"),
			icon_name = prop("application.icon_name"),
			role = prop("media.role"),
			binary = prop("application.process.binary"),
		},
	}
end

--- Parses all sink inputs from JSON list output.
---@param stdout string  Output of: pactl --format=json list sink-inputs
---@return { id: string, state: SinkInputState, meta: SinkInputMeta }[]
local function parse_all_sink_inputs_json(stdout)
	local ok, inputs = pcall(json.decode, stdout)
	if not ok or type(inputs) ~= "table" then
		return {}
	end
	local entries = {}
	for _, inp in ipairs(inputs) do
		entries[#entries + 1] = input_from_json(inp)
	end
	return entries
end

--- Parses a single sink input by id from JSON list output.
---@param stdout string
---@param id string
---@return SinkInputState?, SinkInputMeta?
local function parse_sink_input_by_index_json(stdout, id)
	local ok, inputs = pcall(json.decode, stdout)
	if not ok or type(inputs) ~= "table" then
		return nil, nil
	end
	local target = tonumber(id)
	for _, inp in ipairs(inputs) do
		if inp.index == target then
			local input = input_from_json(inp)
			return input.state, input.meta
		end
	end
	return nil, nil
end

-- ----------------------------------------------------------------------------
-- Load-time format selection
-- ----------------------------------------------------------------------------

local SERVER_DEFAULT_CMD = { "sh", "-c", "pactl get-default-sink; pactl get-default-source" }
local SINK_POLL_CMD, SOURCE_POLL_CMD, INPUT_CMD
local _parse_all_devices, _parse_device_by_index, _parse_all_sink_inputs, _parse_sink_input_by_index
if json.is_c_extension then
	SINK_POLL_CMD = { "sh", "-c", [[pactl get-default-sink; echo "---"; pactl --format=json list sinks]] }
	SOURCE_POLL_CMD = { "sh", "-c", [[pactl get-default-source; echo "---"; pactl --format=json list sources]] }
	INPUT_CMD = { "sh", "-c", "pactl --format=json list sink-inputs" }
	_parse_all_devices = parse_all_devices_json
	_parse_device_by_index = parse_device_by_index_json
	_parse_all_sink_inputs = parse_all_sink_inputs_json
	_parse_sink_input_by_index = parse_sink_input_by_index_json
else
	SINK_POLL_CMD = { "sh", "-c", [[pactl get-default-sink; echo "---"; pactl list sinks]] }
	SOURCE_POLL_CMD = { "sh", "-c", [[pactl get-default-source; echo "---"; pactl list sources]] }
	INPUT_CMD = { "sh", "-c", "pactl list sink-inputs" }
	_parse_all_devices = parse_all_devices_text
	_parse_device_by_index = parse_device_by_index_text
	_parse_all_sink_inputs = parse_all_sink_inputs_text
	_parse_sink_input_by_index = parse_sink_input_by_index_text
end

-- ----------------------------------------------------------------------------
-- Backend
-- ----------------------------------------------------------------------------

---@return AudioBackend
local function create()
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
	local sink_name_to_idx = {}
	local sink_idx_to_name = {}
	local source_name_to_idx = {}
	local source_idx_to_name = {}

	---@param id string
	---@param state SinkInputState
	---@param meta SinkInputMeta
	local function register_input(id, state, meta)
		if not input_handles then
			return
		end
		if meta.icon_name then
			app_icon.by_icon_name(meta.icon_name, function(icon_path)
				meta.app_icon = icon_path
				input_handles.add(id, state, meta)
			end)
		elseif meta.app_name then
			app_icon.by_app_name(meta.app_name, function(icon_path)
				meta.app_icon = icon_path
				input_handles.add(id, state, meta)
			end)
		else
			input_handles.add(id, state, meta)
		end
	end

	local function poll_inputs()
		awful.spawn.easy_async(INPUT_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not input_handles then
				return
			end
			local entries = _parse_all_sink_inputs(stdout)
			for _, entry in ipairs(entries) do
				register_input(entry.id, entry.state, entry.meta)
			end
		end)
	end

	local function poll_sinks()
		awful.spawn.easy_async(SINK_POLL_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not sink_handles then
				return
			end
			local entries = _parse_all_devices(stdout)
			local default_state, default_meta = nil, nil
			for _, entry in ipairs(entries) do
				sink_handles.add(entry.id, entry.state, entry.meta)
				if entry.meta.name then
					sink_name_to_idx[entry.meta.name] = entry.id
					sink_idx_to_name[entry.id] = entry.meta.name
				end
				if entry.state.is_default then
					current_default_sink = entry.meta.name
					current_default_sink_idx = entry.id
					default_state = entry.state
					default_meta = entry.meta
				end
			end
			if on_sink and default_state then
				on_sink(current_default_sink_idx, default_state, default_meta)
			end
		end)
	end

	local function poll_sources()
		awful.spawn.easy_async(SOURCE_POLL_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not source_handles then
				return
			end
			local entries = _parse_all_devices(stdout)
			local default_state, default_meta = nil, nil
			for _, entry in ipairs(entries) do
				source_handles.add(entry.id, entry.state, entry.meta)
				if entry.meta.name then
					source_name_to_idx[entry.meta.name] = entry.id
					source_idx_to_name[entry.id] = entry.meta.name
				end
				if entry.state.is_default then
					current_default_source = entry.meta.name
					current_default_source_idx = entry.id
					default_state = entry.state
					default_meta = entry.meta
				end
			end
			if on_source and default_state then
				on_source(current_default_source_idx, default_state, default_meta)
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
						local parsed = _parse_device_by_index(stdout, idx_str)
						if parsed then
							sink_handles.add(idx_str, parsed.state, parsed.meta)
							if parsed.meta.name then
								sink_name_to_idx[parsed.meta.name] = idx_str
								sink_idx_to_name[idx_str] = parsed.meta.name
							end
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
							local parsed = _parse_device_by_index(stdout, idx_str)
							if parsed then
								sink_handles.update(idx_str, parsed.state)
								if parsed.state.is_default and on_sink then
									on_sink(current_default_sink_idx, parsed.state, parsed.meta)
								end
							end
						end)
					end
				elseif event_type == "remove" then
					if sink_handles then
						local name = sink_idx_to_name[idx_str]
						if name then
							sink_name_to_idx[name] = nil
						end
						sink_idx_to_name[idx_str] = nil
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
						local parsed = _parse_device_by_index(stdout, idx_str)
						if parsed then
							source_handles.add(idx_str, parsed.state, parsed.meta)
							if parsed.meta.name then
								source_name_to_idx[parsed.meta.name] = idx_str
								source_idx_to_name[idx_str] = parsed.meta.name
							end
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
							local parsed = _parse_device_by_index(stdout, idx_str)
							if parsed then
								source_handles.update(idx_str, parsed.state)
								if parsed.state.is_default and on_source then
									on_source(current_default_source_idx, parsed.state, parsed.meta)
								end
							end
						end)
					end
				elseif event_type == "remove" then
					if source_handles then
						local name = source_idx_to_name[idx_str]
						if name then
							source_name_to_idx[name] = nil
						end
						source_idx_to_name[idx_str] = nil
						source_handles.remove(idx_str)
					end
				end
			elseif entity == "server" then
				if pending.server > 0 then
					pending.server = pending.server - 1
					return
				end
				awful.spawn.easy_async(SERVER_DEFAULT_CMD, function(stdout, _, _, exitcode)
					if exitcode ~= 0 then
						return
					end
					local sink_name, source_name = stdout:match("^([^\n]+)\n([^\n]+)")
					if sink_handles and sink_name and sink_name ~= current_default_sink then
						local new_idx = sink_name_to_idx[sink_name]
						if not new_idx then
							poll_sinks()
						else
							if current_default_sink_idx then
								sink_handles.patch(current_default_sink_idx, { is_default = false })
							end
							local s, meta = sink_handles.patch(new_idx, { is_default = true })
							if s and on_sink then
								current_default_sink = sink_name
								current_default_sink_idx = new_idx
								on_sink(new_idx, s, meta)
							end
						end
					end
					if source_handles and source_name and source_name ~= current_default_source then
						local new_idx = source_name_to_idx[source_name]
						if not new_idx then
							poll_sources()
						else
							if current_default_source_idx then
								source_handles.patch(current_default_source_idx, { is_default = false })
							end
							local s, meta = source_handles.patch(new_idx, { is_default = true })
							if s and on_source then
								current_default_source = source_name
								current_default_source_idx = new_idx
								on_source(new_idx, s, meta)
							end
						end
					end
				end)
			elseif entity == "sink-input" then
				if input_handles then
					local idx_str = line:match("#(%d+)")
					local event_type = line:match("Event '(%a+)'")
					if event_type == "remove" and idx_str then
						pending_inputs[idx_str] = nil
						input_handles.remove(idx_str)
					elseif event_type == "new" and idx_str then
						awful.spawn.easy_async(INPUT_CMD, function(stdout, _, _, exitcode)
							if exitcode ~= 0 or not input_handles then
								return
							end
							local s, meta = _parse_sink_input_by_index(stdout, idx_str)
							if s then
								register_input(idx_str, s, meta or {})
							end
						end)
					elseif event_type == "change" and idx_str then
						if pending_inputs[idx_str] and pending_inputs[idx_str] > 0 then
							pending_inputs[idx_str] = pending_inputs[idx_str] - 1
						else
							awful.spawn.easy_async(INPUT_CMD, function(stdout, _, _, exitcode)
								if exitcode ~= 0 or not input_handles then
									return
								end
								local s = _parse_sink_input_by_index(stdout, idx_str)
								if s then
									input_handles.update(idx_str, s)
								end
							end)
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
		sink_name_to_idx = {}
		sink_idx_to_name = {}
		source_name_to_idx = {}
		source_idx_to_name = {}
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
			if sink_handles then
				if current_default_sink_idx and current_default_sink_idx ~= idx then
					sink_handles.patch(current_default_sink_idx, { is_default = false })
				end
				local s, meta = sink_handles.patch(idx, { is_default = true })
				if s and on_sink then
					current_default_sink = meta.name
					current_default_sink_idx = idx
					on_sink(idx, s, meta)
				end
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
			if source_handles then
				if current_default_source_idx and current_default_source_idx ~= idx then
					source_handles.patch(current_default_source_idx, { is_default = false })
				end
				local s, meta = source_handles.patch(idx, { is_default = true })
				if s and on_source then
					current_default_source = meta.name
					current_default_source_idx = idx
					on_source(idx, s, meta)
				end
			end
			if cb then
				cb()
			end
		end)
	end

	sink_api.set_port = function(idx, port_name, cb)
		pending_sinks[idx] = (pending_sinks[idx] or 0) + 1
		awful.spawn.easy_async({ "pactl", "set-sink-port", idx, port_name }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				if pending_sinks[idx] and pending_sinks[idx] > 0 then
					pending_sinks[idx] = pending_sinks[idx] - 1
				end
				return
			end
			if sink_handles then
				sink_handles.patch(idx, { port = port_name, port_type = derive_port_type(port_name) })
			end
			if cb then
				cb()
			end
		end)
	end

	source_api.set_port = function(idx, port_name, cb)
		pending_sources[idx] = (pending_sources[idx] or 0) + 1
		awful.spawn.easy_async({ "pactl", "set-source-port", idx, port_name }, function(_, _, _, exitcode)
			if exitcode ~= 0 then
				if pending_sources[idx] and pending_sources[idx] > 0 then
					pending_sources[idx] = pending_sources[idx] - 1
				end
				return
			end
			if source_handles then
				source_handles.patch(idx, { port = port_name, port_type = derive_port_type(port_name) })
			end
			if cb then
				cb()
			end
		end)
	end

	local function after_set_input(id, cb)
		awful.spawn.easy_async(INPUT_CMD, function(stdout, _, _, exitcode)
			if exitcode ~= 0 then
				return
			end
			local s = _parse_sink_input_by_index(stdout, id)
			if s and cb then
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
	-- port parse functions
	parse_ports_text = parse_ports_text,
	-- text parse functions
	parse_all_devices = parse_all_devices_text,
	find_device_block_by_index = find_device_block_by_index,
	parse_device_block = parse_device_block,
	find_sink_input_block = find_sink_input_block,
	parse_sink_input_block = parse_sink_input_block,
	-- json parse functions
	parse_all_devices_json = parse_all_devices_json,
	parse_device_by_index_json = parse_device_by_index_json,
	parse_all_sink_inputs_json = parse_all_sink_inputs_json,
	parse_sink_input_by_index_json = parse_sink_input_by_index_json,
}

return setmetatable(Pulse, {
	__call = function(_)
		return create()
	end,
})
