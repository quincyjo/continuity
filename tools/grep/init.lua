-- Grep tool — programmatic wrapper around rg / grep.
-- Selects the highest-priority backend available on PATH at load time.
--
-- Usage:
--   local grep = require("continuity.tools.grep")
--   grep(opts, cb)         -- async: cb(results, exit_code)
--   grep.stream(opts, cb)  -- streaming: cb(batch, nil) …, cb(nil, exit_code)

local awful = require("awful") -- used in grep() and grep.stream()
local gears = require("gears")

local unpack = unpack or unpack -- luacheck: globals unpack

local rg = require("continuity.tools.grep.backends.rg")
local grep_cmd = require("continuity.tools.grep.backends.grep")

---@class GrepOpts
---@field pattern           string
---@field path              string|string[]  -- single path or array of paths to search
---@field fixed_string?     boolean
---@field case_insensitive? boolean
---@field follow_links?     boolean          -- rg: -L; grep: -R instead of -r
---@field include?          string
---@field exclude?          string
---@field type?             string
---@field max_depth?        integer   -- rg only; silently ignored by grep backend

---@class GrepResult
---@field filepath    string
---@field line_number integer
---@field text        string

---@alias GrepCallback       fun(results: GrepResult[], exit_code: integer)
---@alias GrepStreamCallback fun(batch: GrepResult[]|nil, exit_code: integer|nil)

-- ─── Backend selection ───────────────────────────────────────────────────────

local BACKENDS = { rg, grep_cmd }
local selected ---@type GrepBackend|nil

for _, backend in ipairs(BACKENDS) do
	local f = io.popen("command -v " .. backend.command .. " 2>/dev/null")
	if f then
		if f:read("*l") then
			selected = backend
			f:close()
			break
		end
		f:close()
	end
end

-- ─── Normalization ───────────────────────────────────────────────────────────

-- Unlike the find tool, normalize does not accept a plain string. Both
-- pattern and path are required, making a single-value shorthand ambiguous.
---@param opts table
---@return GrepOpts
local function normalize(opts)
	local result = {}
	for k, v in pairs(opts) do
		if type(k) == "string" then
			result[k] = v
		end
	end
	if opts[1] ~= nil then
		result.pattern = opts[1]
	end
	if opts[2] ~= nil then
		result.path = opts[2]
	end
	if opts[3] ~= nil then
		gears.debug.print_warning("grep: only opts[1] and opts[2] are used as positional; opts[3+] ignored")
	end
	return result
end

-- ─── Spawn helpers ───────────────────────────────────────────────────────────

-- awful.spawn's underlying GLib IO layer uses C strings, which are
-- null-terminated — so a NUL byte in rg/grep output (from --null/-Z) would
-- truncate each line before the line-number field ever reaches Lua.
-- Work around this by wrapping every invocation in a sh pipeline that
-- translates NUL (octal \000) -> TAB (octal \011) before Lua sees it.
-- The "$@" form passes each argv element as a separate word, so no
-- shell-quoting or injection concerns apply.
local PIPE_NUL_TO_TAB = [["$@" | tr '\000' '\011']]

local function make_argv(inner)
	local argv = { "sh", "-c", PIPE_NUL_TO_TAB, "sh" }
	for _, a in ipairs(inner) do
		argv[#argv + 1] = a
	end
	return argv
end

-- ─── Parsing ─────────────────────────────────────────────────────────────────

-- Parse a line in the format emitted by rg --null / grep -Z, after the NUL
-- byte has been translated to a TAB by the shell wrapper above.
-- Format: <filepath> TAB <linenum> ":" <text>
---@param line   string
---@param intern table<string, string>
---@return GrepResult|nil
local function parse_line(line, intern)
	local raw_path, remainder = line:match("^([^\t]*)\t(.+)$")
	if not raw_path then
		return nil
	end
	local raw_lnum, text = remainder:match("^(%d+):(.*)$")
	if not raw_lnum then
		return nil
	end
	intern[raw_path] = intern[raw_path] or raw_path
	return {
		filepath = intern[raw_path],
		line_number = tonumber(raw_lnum),
		text = text,
	}
end

-- ─── Public API ──────────────────────────────────────────────────────────────

local grep = {}

---@param opts_raw table
---@param cb GrepStreamCallback
function grep.stream(opts_raw, cb)
	local opts = normalize(opts_raw or {})
	if not selected then
		gears.debug.print_warning("grep: no backend available (rg or grep not on PATH)")
		cb(nil, 1)
		return
	end
	local argv = make_argv({ selected.command, unpack(selected.build_args(opts)) })
	local intern = {}
	local buffer = {}
	local timer = gears.timer({
		timeout = 0,
		single_shot = true,
		callback = function()
			if #buffer > 0 then
				cb(buffer, nil)
				buffer = {}
			end
		end,
	})
	awful.spawn.with_line_callback(argv, {
		stdout = function(line)
			local result = parse_line(line, intern)
			if result then
				buffer[#buffer + 1] = result
				timer:again()
			end
		end,
		exit = function(_, exit_code)
			timer:stop()
			if #buffer > 0 then
				cb(buffer, nil)
				buffer = {}
			end
			cb(nil, exit_code)
		end,
	})
end

-- ─── Test helpers ────────────────────────────────────────────────────────────

grep._normalize = normalize
grep._parse_line = parse_line
grep._set_backend = function(b)
	selected = b
end

return setmetatable(grep, {
	__call = function(_, opts_raw, cb)
		local opts = normalize(opts_raw or {})
		if not selected then
			gears.debug.print_warning("grep: no backend available (rg or grep not on PATH)")
			cb({}, 1)
			return
		end
		local argv = make_argv({ selected.command, unpack(selected.build_args(opts)) })
		local intern = {}
		awful.spawn.easy_async(argv, function(stdout, _, _, exit_code)
			local results = {}
			for line in stdout:gmatch("([^\n]+)") do
				local result = parse_line(line, intern)
				if result then
					results[#results + 1] = result
				end
			end
			cb(results, exit_code)
		end)
	end,
})
