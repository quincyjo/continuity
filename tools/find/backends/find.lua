-- find(1) backend for the find tool.
-- build_args(opts) returns an argv fragment (no command name prefix).
-- Path is always the first token; find(1) requires an explicit path.
-- Hidden exclusion (-not -name .*) is emitted before -exec so exec
-- does not run on dotfiles.

---@type table<string, string>
local TYPE_MAP = {
	file = "f",
	directory = "d",
	symlink = "l",
	block = "b",
	char = "c",
	pipe = "p",
	socket = "s",
}

---@class FindBackend
local find_cmd = {}

find_cmd.command = "find"

---@param opts FindOpts
---@return string[]
function find_cmd.build_args(opts)
	local args = {}
	if type(opts.path) == "table" then
		for _, p in ipairs(opts.path) do
			args[#args + 1] = p
		end
	else
		args[#args + 1] = opts.path or "."
	end
	if opts.maxdepth then
		args[#args + 1] = "-maxdepth"
		args[#args + 1] = tostring(opts.maxdepth)
	end
	if opts.type then
		args[#args + 1] = "-type"
		args[#args + 1] = TYPE_MAP[opts.type] or opts.type
	end
	if opts.extension then
		args[#args + 1] = "-name"
		args[#args + 1] = "*." .. opts.extension
	end
	if opts.pattern then
		args[#args + 1] = "-regex"
		args[#args + 1] = ".*" .. opts.pattern .. ".*"
	end
	if not opts.hidden then
		-- Suppresses dotfiles by filename, but does not prune dot-directories
		-- from traversal. This differs from fd's --hidden which suppresses both.
		-- Use hidden=true and filter manually if dot-directory traversal matters.
		args[#args + 1] = "-not"
		args[#args + 1] = "-name"
		args[#args + 1] = ".*"
	end
	if opts.exec then
		-- exec is split on whitespace; quoted arguments containing spaces are not supported.
		args[#args + 1] = "-exec"
		for token in opts.exec:gmatch("%S+") do
			args[#args + 1] = token
		end
		args[#args + 1] = ";"
	end
	return args
end

return find_cmd
