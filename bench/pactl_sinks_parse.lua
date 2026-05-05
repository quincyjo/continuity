-- Benchmarks three approaches to parsing pactl list sinks output.
-- Two scenarios, each run with N=1..5 sinks:
--   1. parse default  — find and parse the default (target) sink only
--   2. parse all      — parse every sink in the list
--
-- Input is constructed by concatenating N-1 copies of the secondary
-- sink followed by the default sink, simulating a realistic list where
-- the target is at the end.
--
-- Fixtures (single sinks; JSON is pretty-printed for readability):
--   bench/fixtures/sink_default.txt    -- target sink, text format
--   bench/fixtures/sink_secondary.txt  -- non-target sink, text format
--   bench/fixtures/sink_default.json   -- target sink, JSON object
--   bench/fixtures/sink_secondary.json -- non-target sink, JSON object
--
-- Run: lua bench/pactl_sinks_parse.lua

package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local ITERATIONS = 10000
local N_MAX = 5

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

local default_text = read_fixture("bench/fixtures/sink_default.txt")
local secondary_text = read_fixture("bench/fixtures/sink_secondary.txt")
local default_json_pretty = read_fixture("bench/fixtures/sink_default.json")
local secondary_json_pretty = read_fixture("bench/fixtures/sink_secondary.json")

local default_name = default_text:match("\tName: ([^\n]+)")
if not default_name then
	error("could not extract Name from sink_default.txt")
end
print("Default sink: " .. default_name)

-- ----------------------------------------------------------------------------
-- JSON modules
-- ----------------------------------------------------------------------------

local ok_c, c_json = pcall(require, "json")
local lua_json = require("continuity.util.json.json_lua")

-- Compact the pretty-printed fixture objects once (realistic pactl output format).
-- Uses lua_json which is always available; all parsers receive the same string.
local default_json = lua_json.encode(lua_json.decode(default_json_pretty))
local secondary_json = lua_json.encode(lua_json.decode(secondary_json_pretty))

-- ----------------------------------------------------------------------------
-- Build N-sink inputs: (N-1) secondary sinks followed by the default
-- ----------------------------------------------------------------------------

local text_inputs, json_inputs = {}, {}
for n = 1, N_MAX do
	local text_parts, json_parts = {}, {}
	for i = 1, n - 1 do
		text_parts[i] = secondary_text
		json_parts[i] = secondary_json
	end
	text_parts[n] = default_text
	json_parts[n] = default_json
	text_inputs[n] = table.concat(text_parts, "\n")
	json_inputs[n] = "[" .. table.concat(json_parts, ",") .. "]"
end

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
-- Shared state extractors
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
	local port = (sink.active_port ~= "") and sink.active_port or nil
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

-- ----------------------------------------------------------------------------
-- Method 1: pattern-based
-- ----------------------------------------------------------------------------

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
	return block and block_to_state(block) or nil
end

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
-- ----------------------------------------------------------------------------

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

local parse_default_json_c = ok_c and make_json_parse_default(c_json) or nil
local parse_default_json_lua = make_json_parse_default(lua_json)
local parse_all_json_c = ok_c and make_json_parse_all(c_json) or nil
local parse_all_json_lua = make_json_parse_all(lua_json)

-- ----------------------------------------------------------------------------
-- Sanity check
-- ----------------------------------------------------------------------------

local function state_str(s)
	if s == nil then
		return "nil"
	end
	return string.format(
		"name=%s level=%d muted=%s port=%s",
		tostring(s.name),
		s.level,
		tostring(s.muted),
		tostring(s.port)
	)
end

local function states_str(arr)
	if arr == nil then
		return "nil"
	end
	local parts = {}
	for i, s in ipairs(arr) do
		parts[i] = state_str(s)
	end
	return table.concat(parts, " | ")
end

-- Runs fn_pat, fn_c (optional), fn_lua and checks all agree.
-- Prints ✓ on pass; full output on failure.
local function sanity(label, to_str, fn_pat, fn_c, fn_lua)
	local s_pat = to_str(fn_pat())
	local s_c = fn_c and to_str(fn_c()) or s_pat
	local s_lua = to_str(fn_lua())
	if s_pat == s_c and s_pat == s_lua then
		print("  " .. label .. " ✓")
	else
		print("  " .. label .. " FAIL")
		print("    pattern:    " .. s_pat)
		if fn_c then
			print("    c-binding:  " .. s_c)
		end
		print("    lua-native: " .. s_lua)
	end
end

-- Use N=2 so both sink types appear in the input.
print("\nSanity check:")
sanity(
	"parse default (N=2)",
	state_str,
	function()
		return parse_default_pattern(text_inputs[2], default_name)
	end,
	parse_default_json_c and function()
		return parse_default_json_c(json_inputs[2], default_name)
	end,
	function()
		return parse_default_json_lua(json_inputs[2], default_name)
	end
)
sanity(
	"parse all     (N=2)",
	states_str,
	function()
		return parse_all_pattern(text_inputs[2])
	end,
	parse_all_json_c and function()
		return parse_all_json_c(json_inputs[2])
	end,
	function()
		return parse_all_json_lua(json_inputs[2])
	end
)

-- ----------------------------------------------------------------------------
-- Benchmark
-- ----------------------------------------------------------------------------

local function measure(fn)
	local t0 = os.clock()
	for _ = 1, ITERATIONS do
		fn()
	end
	return (os.clock() - t0) / ITERATIONS * 1e6
end

local function fmt_us(n)
	return string.format("%10.2f µs", n)
end

local NA = string.rep(" ", 10) .. "[n/a]  "
local HDR = string.format("  %3s  %13s  %13s  %13s", "N", "pattern", "c-binding", "lua-native")
local SEP = string.rep("-", #HDR)

-- make_pat(n), make_c(n), make_lua(n) each return a thunk for iteration N.
local function run_table(label, make_pat, make_c, make_lua)
	print(string.format("\n%s  (%d iterations)", label, ITERATIONS))
	print(SEP)
	print(HDR)
	print(SEP)
	for n = 1, N_MAX do
		local t_pat = measure(make_pat(n))
		local t_c_str = make_c and fmt_us(measure(make_c(n))) or NA
		local t_lua = measure(make_lua(n))
		print(string.format("  %3d  %s  %s  %s", n, fmt_us(t_pat), t_c_str, fmt_us(t_lua)))
	end
	print(SEP)
end

run_table(
	"Benchmark 1: parse default sink",
	function(n)
		return function()
			parse_default_pattern(text_inputs[n], default_name)
		end
	end,
	parse_default_json_c
		and function(n)
			return function()
				parse_default_json_c(json_inputs[n], default_name)
			end
		end,
	function(n)
		return function()
			parse_default_json_lua(json_inputs[n], default_name)
		end
	end
)

run_table(
	"Benchmark 2: parse all sinks",
	function(n)
		return function()
			parse_all_pattern(text_inputs[n])
		end
	end,
	parse_all_json_c and function(n)
		return function()
			parse_all_json_c(json_inputs[n])
		end
	end,
	function(n)
		return function()
			parse_all_json_lua(json_inputs[n])
		end
	end
)
