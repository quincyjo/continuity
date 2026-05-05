exclude_files = { ".luarocks/**", "lua/continuity/util/json/json_lua.lua" }

read_globals = {
	"awesome",
	"screen",
	"tag",
}
globals = {
	"client",
}

self = false
max_string_line_length = false
max_comment_line_length = false

-- Spec files monkey-patch globals for test isolation.
files["spec/"] = {
	globals = {
		"awesome", -- overrides read_globals; allows awesome.kill = ... etc.
		"os", -- allows os.time = ... for time-travel tests
	},
}
