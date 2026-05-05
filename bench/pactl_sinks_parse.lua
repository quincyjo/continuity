-- Benchmarks three approaches to parsing pactl list sinks output.
-- Two scenarios per approach:
--   1. parse default  — find and parse the default sink only
--   2. parse all      — parse every sink in the list
--
-- Fixture setup (run from project root):
--   pactl get-default-sink > bench/fixtures/pactl_list_sinks_default.txt
--   pactl list sinks       > bench/fixtures/pactl_list_sinks.txt
--   pactl -f json list sinks > bench/fixtures/pactl_list_sinks.json
--
-- Run: lua bench/pactl_sinks_parse.lua

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local ITERATIONS = 10000

-- ----------------------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------------------

local function read_fixture(path)
	local f, err = io.open(path, "r")
	if not f then
		error("Missing fixture: " .. path .. "\n  " .. (err or ""))
	end
	local content = f:read("*a")
	f:close()
	return content
end

local default_name = read_fixture("bench/fixtures/pactl_list_sinks_default.txt"):match("^([^\n]+)")
local text_fixture = read_fixture("bench/fixtures/pactl_list_sinks.txt")
local json_fixture = read_fixture("bench/fixtures/pactl_list_sinks.json")

if not default_name or default_name == "" then
	error("pactl_list_sinks_default.txt is empty or malformed")
end

print("Default sink: " .. default_name)

-- ----------------------------------------------------------------------------
-- Shared derive helpers (same logic as pulse backend)
-- ----------------------------------------------------------------------------

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
-- Shared block-to-state extractor (used by both pattern scenarios)
-- ----------------------------------------------------------------------------

local function block_to_state(block)
	local level = tonumber(block:match("/%s+(%d+)%%"))
	local muted = block:match("Mute: (%a+)") == "yes"
	local port = block:match("\tActive Port: ([^\n]+)")
	local name = block:match("\tName: ([^\n]+)")
	local description = block:match("\tDescription: ([^\n]+)")
	return {
		name = name,
		description = description,
		level = level or 0,
		muted = muted or false,
		port = port,
		port_type = port and derive_port_type(port) or nil,
		connection = name and derive_connection(name) or nil,
	}
end

-- ----------------------------------------------------------------------------
-- Method 1: pattern-based
-- ----------------------------------------------------------------------------

--- Finds and returns the tab-indented block whose content contains device_name.
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

local function parse_default_pattern(list, sink_name)
	local block = find_device_block(list, sink_name)
	if not block then
		return nil
	end
	return block_to_state(block)
end

--- Parses every sink block, returning an array of states.
local function parse_all_pattern(list)
	local results = {}
	local current_lines = {}
	local in_block = false

	local function flush()
		if in_block and #current_lines > 0 then
			results[#results + 1] = block_to_state(table.concat(current_lines, "\n"))
		end
	end

	for line in (list .. "\n"):gmatch("([^\n]*)\n") do
		if line:match("^%u%l+ #%d+") then
			flush()
			in_block = true
			current_lines = {}
		elseif in_block then
			current_lines[#current_lines + 1] = line
		end
	end
	flush()
	return results
end

-- ----------------------------------------------------------------------------
-- Method 2 & 3: JSON-based
--
-- Expects the output of `pactl -f json list sinks`: a JSON array of sink
-- objects. Each sink has at minimum:
--   name        string
--   description string
--   mute        boolean
--   active_port string
--   volume      { [channel]: { value_percent: "N%" } }
-- ----------------------------------------------------------------------------

local function sink_to_state(sink)
	local total, count = 0, 0
	if type(sink.volume) == "table" then
		for _, ch in pairs(sink.volume) do
			if type(ch) == "table" and type(ch.value_percent) == "string" then
				local n = tonumber(ch.value_percent:match("(%d+)%%"))
				if n then
					total = total + n
					count = count + 1
				end
			end
		end
	end
	local level = count > 0 and math.floor(total / count) or 0
	local port = sink.active_port ~= "" and sink.active_port or nil
	return {
		name = sink.name,
		description = sink.description,
		level = level,
		muted = sink.mute or false,
		port = port,
		port_type = port and derive_port_type(port) or nil,
		connection = sink.name and derive_connection(sink.name) or nil,
	}
end

local function make_json_parse_default(json_mod)
	return function(json_str, sink_name)
		local sinks = json_mod.decode(json_str)
		if type(sinks) ~= "table" then
			return nil
		end
		for _, s in ipairs(sinks) do
			if s.name == sink_name then
				return sink_to_state(s)
			end
		end
		return nil
	end
end

local function make_json_parse_all(json_mod)
	return function(json_str)
		local sinks = json_mod.decode(json_str)
		if type(sinks) ~= "table" then
			return nil
		end
		local results = {}
		for _, s in ipairs(sinks) do
			results[#results + 1] = sink_to_state(s)
		end
		return results
	end
end

local ok_c, c_json = pcall(require, "json")
local lua_json = require("continuity.util.json.json_lua")

local parse_default_json_c = ok_c and make_json_parse_default(c_json) or nil
local parse_default_json_lua = make_json_parse_default(lua_json)
local parse_all_json_c = ok_c and make_json_parse_all(c_json) or nil
local parse_all_json_lua = make_json_parse_all(lua_json)

-- ----------------------------------------------------------------------------
-- Sanity check
-- ----------------------------------------------------------------------------

local function check_single(label, result)
	if result == nil then
		io.stderr:write("WARN: " .. label .. " returned nil — check fixture and parser\n")
	else
		print(
			string.format(
				"  %-28s name=%-45s level=%d muted=%s port=%s",
				label,
				tostring(result.name),
				result.level,
				tostring(result.muted),
				tostring(result.port)
			)
		)
	end
end

local function check_all(label, results)
	if results == nil then
		io.stderr:write("WARN: " .. label .. " returned nil — check fixture and parser\n")
	else
		print(string.format("  %-28s [%d sinks]", label, #results))
		for _, r in ipairs(results) do
			print(
				string.format(
					"    name=%-45s level=%d muted=%s port=%s",
					tostring(r.name),
					r.level,
					tostring(r.muted),
					tostring(r.port)
				)
			)
		end
	end
end

print("\nSanity check — parse default:")
check_single("pattern", parse_default_pattern(text_fixture, default_name))
if parse_default_json_c then
	check_single("json (c-binding)", parse_default_json_c(json_fixture, default_name))
end
check_single("json (lua native)", parse_default_json_lua(json_fixture, default_name))

print("\nSanity check — parse all:")
check_all("pattern", parse_all_pattern(text_fixture))
if parse_all_json_c then
	check_all("json (c-binding)", parse_all_json_c(json_fixture))
end
check_all("json (lua native)", parse_all_json_lua(json_fixture))

-- ----------------------------------------------------------------------------
-- Benchmark
-- ----------------------------------------------------------------------------

local function bench(name, fn)
	local t0 = os.clock()
	for _ = 1, ITERATIONS do
		fn()
	end
	local elapsed = os.clock() - t0
	local mean_us = (elapsed / ITERATIONS) * 1e6
	print(string.format("  %-30s  %8.2f µs/iter  (%d iters, %.3fs total)", name, mean_us, ITERATIONS, elapsed))
end

local SEP = string.rep("-", 72)

print(string.format("\nBenchmark 1: parse default sink  (%d iterations)", ITERATIONS))
print(SEP)
bench("pattern", function()
	parse_default_pattern(text_fixture, default_name)
end)
if parse_default_json_c then
	bench("json (c-binding)", function()
		parse_default_json_c(json_fixture, default_name)
	end)
else
	print("  json (c-binding)               [skipped — lua-json c ext not available]")
end
bench("json (lua native)", function()
	parse_default_json_lua(json_fixture, default_name)
end)
print(SEP)

print(string.format("\nBenchmark 2: parse all sinks  (%d iterations)", ITERATIONS))
print(SEP)
bench("pattern", function()
	parse_all_pattern(text_fixture)
end)
if parse_all_json_c then
	bench("json (c-binding)", function()
		parse_all_json_c(json_fixture)
	end)
else
	print("  json (c-binding)               [skipped — lua-json c ext not available]")
end
bench("json (lua native)", function()
	parse_all_json_lua(json_fixture)
end)
print(SEP)
