-- grep(1) backend for the grep tool.
-- build_args(opts) returns an argv fragment (no command name prefix).
-- Forced flags: -r -n -H -Z
--   -r  recursive search
--   -n  include line numbers
--   -H  always print filepath (needed for single-file searches)
--   -Z  NUL byte after filepath for unambiguous parsing
-- type is translated to --include=GLOB via TYPE_MAP.
-- Unknown types fall back to --include=*.TYPE.
-- Note: max_depth is not supported by grep(1) and is silently ignored.
--       Use rg backend for max_depth support.

---@type table<string, string>
local TYPE_MAP = {
	lua = "*.lua",
	python = "*.py",
	py = "*.py",
	js = "*.js",
	ts = "*.ts",
	c = "*.c",
	cpp = "*.cpp",
	go = "*.go",
	rust = "*.rs",
	sh = "*.sh",
	html = "*.html",
	css = "*.css",
	json = "*.json",
	yaml = "*.yaml",
	toml = "*.toml",
	xml = "*.xml",
	md = "*.md",
}

---@class GrepBackend
local grep_cmd = {}

grep_cmd.command = "grep"

---@param opts GrepOpts
---@return string[]
function grep_cmd.build_args(opts)
	local args = { opts.follow_links and "-R" or "-r", "-n", "-H", "-Z" }
	if opts.fixed_string then
		args[#args + 1] = "-F"
	end
	if opts.case_insensitive then
		args[#args + 1] = "-i"
	end
	if opts.include then
		args[#args + 1] = "--include=" .. opts.include
	end
	if opts.exclude then
		args[#args + 1] = "--exclude=" .. opts.exclude
	end
	-- When both include and type are set, grep ANDs both --include globs.
	if opts.type then
		local glob = TYPE_MAP[opts.type] or ("*." .. opts.type)
		args[#args + 1] = "--include=" .. glob
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

return grep_cmd
