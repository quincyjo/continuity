-- rg backend for the grep tool.
-- build_args(opts) returns an argv fragment (no command name prefix).
-- Forced flags: --with-filename --no-heading --line-number --null
--   --with-filename  always print filepath, even for single-file searches
--   --no-heading     flat output: one result per line with filepath prefix
--   --line-number    include line numbers in output
--   --null           NUL byte after filepath for unambiguous parsing

---@class GrepBackend
local rg = {}

rg.command = "rg"

---@param opts GrepOpts
---@return string[]
function rg.build_args(opts)
	local args = { "--with-filename", "--no-heading", "--line-number", "--null" }
	if opts.follow_links then
		args[#args + 1] = "-L"
	end
	if opts.fixed_string then
		args[#args + 1] = "-F"
	end
	if opts.case_insensitive then
		args[#args + 1] = "-i"
	end
	if opts.max_depth then
		args[#args + 1] = "--max-depth"
		args[#args + 1] = tostring(opts.max_depth)
	end
	if opts.include then
		args[#args + 1] = "--glob"
		args[#args + 1] = opts.include
	end
	if opts.exclude then
		args[#args + 1] = "--glob"
		args[#args + 1] = "!" .. opts.exclude
	end
	if opts.type then
		args[#args + 1] = "--type"
		args[#args + 1] = opts.type
	end
	args[#args + 1] = opts.pattern
	if type(opts.path) == "table" then
		for _, p in ipairs(opts.path) do
			args[#args + 1] = p
		end
	else
		args[#args + 1] = opts.path
	end
	return args
end

return rg
