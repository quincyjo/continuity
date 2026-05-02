-- Find tool — programmatic wrapper around fd / find.
-- Selects the highest-priority backend available on PATH at load time.
--
-- Usage:
--   local find = require("continuity.tools.find")
--   find(opts, cb)         -- async: cb(results, exit_code)
--   find.stream(opts, cb)  -- streaming: cb(batch, nil) …, cb(nil, exit_code)

local awful = require("awful")
local gears = require("gears")

local unpack = unpack or table.unpack -- luacheck: globals unpack

local fd = require("continuity.tools.find.backends.fd")
local find_cmd = require("continuity.tools.find.backends.find")

---@class FindOpts
---@field pattern?   string
---@field path?      string|string[]
---@field maxdepth?  integer
---@field type?      "file"|"directory"|"symlink"|"block"|"char"|"pipe"|"socket"
---@field extension? string
---@field exec?      string
---@field hidden?    boolean

---@alias FindCallback       fun(results: string[], exit_code: integer)
---@alias FindStreamCallback fun(batch: string[]|nil, exit_code: integer|nil)

-- ─── Backend selection ───────────────────────────────────────────────────────

local BACKENDS = { fd, find_cmd }
local selected ---@type FindBackend|nil

---@param cmd string
---@return boolean
local function check_command(cmd)
	local f = io.popen("command -v " .. cmd .. " 2>/dev/null")
	if f then
		if f:read("*l") then
			f:close()
			return true
		end
		f:close()
	end
	return false
end

for _, backend in ipairs(BACKENDS) do
	if check_command(backend.command) then
		selected = backend
		break
	end
end

-- ─── Normalization ───────────────────────────────────────────────────────────

---@param opts string|table
---@return FindOpts
local function normalize(opts)
	if type(opts) == "string" then
		return { pattern = opts }
	end
	local result = {}
	for k, v in pairs(opts) do
		if type(k) == "string" then
			result[k] = v
		end
	end
	if opts[1] ~= nil then
		if opts[2] ~= nil then
			gears.debug.print_warning("find: only opts[1] is used as positional; opts[2+] ignored")
		end
		result.pattern = opts[1]
	end
	return result
end

-- ─── Public API ──────────────────────────────────────────────────────────────

local find = {}

---@return ModuleHealth
function find.checkhealth()
	local backends_items = {}
	for _, backend in ipairs(BACKENDS) do
		if check_command(backend.command) then
			backends_items[#backends_items + 1] = {
				status = "ok",
				details = backend.command .. " found",
			}
		else
			backends_items[#backends_items + 1] = {
				status = "warning",
				details = backend.command .. " not found",
			}
		end
	end
	return {
		name = "find",
		sections = {
			{
				label = "General",
				items = {
					{
						status = selected and "ok" or "error",
						details = selected and "using " .. selected.command
							or "no backend available (fd or find not on PATH)",
					},
				},
			},
			{
				label = "Backends",
				items = backends_items,
			},
		},
	}
end

---@param opts_raw string|FindOpts
---@param cb FindStreamCallback
function find.stream(opts_raw, cb)
	local opts = normalize(opts_raw or {})
	if not selected then
		gears.debug.print_warning("find: no backend available (fd or find not on PATH)")
		cb(nil, 1)
		return
	end
	local argv = { selected.command, unpack(selected.build_args(opts)) }
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
			buffer[#buffer + 1] = line
			timer:again()
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

find._normalize = normalize
find._set_backend = function(b)
	selected = b
end

return setmetatable(find, {
	__call = function(_, opts_raw, cb)
		local opts = normalize(opts_raw or {})
		if not selected then
			gears.debug.print_warning("find: no backend available (fd or find not on PATH)")
			cb({}, 1)
			return
		end
		local argv = { selected.command, unpack(selected.build_args(opts)) }
		awful.spawn.easy_async(argv, function(stdout, _, _, exit_code)
			local results = {}
			for line in stdout:gmatch("([^\n]+)") do
				results[#results + 1] = line
			end
			cb(results, exit_code)
		end)
	end,
})
