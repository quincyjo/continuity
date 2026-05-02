-- fd backend for the find tool.
-- build_args(opts) returns an argv fragment (no command name prefix).

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
local fd = {}

fd.command = "fd"

---@param opts FindOpts
---@return string[]
function fd.build_args(opts)
	local args = {}
	if opts.maxdepth then
		args[#args + 1] = "--max-depth"
		args[#args + 1] = tostring(opts.maxdepth)
	end
	if opts.type then
		args[#args + 1] = "--type"
		args[#args + 1] = TYPE_MAP[opts.type] or opts.type
	end
	if opts.extension then
		args[#args + 1] = "--extension"
		args[#args + 1] = opts.extension
	end
	if opts.hidden then
		args[#args + 1] = "--hidden"
	end
	if opts.exec then
		-- exec is split on whitespace; quoted arguments containing spaces are not supported.
		args[#args + 1] = "--exec"
		for token in opts.exec:gmatch("%S+") do
			args[#args + 1] = token
		end
		args[#args + 1] = ";"
	end
	if opts.pattern then
		args[#args + 1] = "--regex"
		args[#args + 1] = opts.pattern
	end
	if type(opts.path) == "table" then
		for _, p in ipairs(opts.path) do
			args[#args + 1] = p
		end
	else
		args[#args + 1] = opts.path
	end
	return args
end

return fd
