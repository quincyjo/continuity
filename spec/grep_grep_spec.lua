require("spec.support.awesome_mocks")
local grep_cmd = require("continuity.tools.grep.backends.grep")

local function has_token(args, t)
	for _, v in ipairs(args) do
		if v == t then
			return true
		end
	end
	return false
end

describe("grep backend", function()
	it("has command 'grep'", function()
		assert.equals("grep", grep_cmd.command)
	end)

	describe("build_args", function()
		it("always starts with -r -n -H -Z", function()
			local args = grep_cmd.build_args({ pattern = "foo", path = "/home" })
			assert.equals("-r", args[1])
			assert.equals("-n", args[2])
			assert.equals("-H", args[3])
			assert.equals("-Z", args[4])
		end)

		it("appends pattern then path as the final two tokens", function()
			local args = grep_cmd.build_args({ pattern = "foo", path = "/home" })
			assert.equals("foo", args[#args - 1])
			assert.equals("/home", args[#args])
		end)

		it("adds -F for fixed_string", function()
			assert.is_true(has_token(grep_cmd.build_args({ pattern = "f", path = ".", fixed_string = true }), "-F"))
		end)

		it("omits -F when fixed_string is false", function()
			assert.is_false(has_token(grep_cmd.build_args({ pattern = "f", path = ".", fixed_string = false }), "-F"))
		end)

		it("adds -i for case_insensitive", function()
			assert.is_true(has_token(grep_cmd.build_args({ pattern = "f", path = ".", case_insensitive = true }), "-i"))
		end)

		it("omits -i when case_insensitive is false", function()
			assert.is_false(
				has_token(grep_cmd.build_args({ pattern = "f", path = ".", case_insensitive = false }), "-i")
			)
		end)

		it("ignores max_depth (not supported by grep)", function()
			local args = grep_cmd.build_args({ pattern = "f", path = ".", max_depth = 3 })
			for i = 1, #args do
				assert.not_equals("--max-depth", args[i])
			end
		end)

		it("adds --include=GLOB for include", function()
			assert.is_true(
				has_token(grep_cmd.build_args({ pattern = "f", path = ".", include = "*.lua" }), "--include=*.lua")
			)
		end)

		it("adds --exclude=GLOB for exclude", function()
			assert.is_true(
				has_token(
					grep_cmd.build_args({ pattern = "f", path = ".", exclude = "*.min.js" }),
					"--exclude=*.min.js"
				)
			)
		end)

		it("maps known type 'lua' to --include=*.lua", function()
			assert.is_true(
				has_token(grep_cmd.build_args({ pattern = "f", path = ".", type = "lua" }), "--include=*.lua")
			)
		end)

		it("maps known type 'python' to --include=*.py", function()
			assert.is_true(
				has_token(grep_cmd.build_args({ pattern = "f", path = ".", type = "python" }), "--include=*.py")
			)
		end)

		it("falls back to --include=*.TYPE for unknown type", function()
			assert.is_true(
				has_token(grep_cmd.build_args({ pattern = "f", path = ".", type = "xyz" }), "--include=*.xyz")
			)
		end)

		it("produces correct full argv for combined opts", function()
			local args = grep_cmd.build_args({
				pattern = "foo",
				path = "/src",
				fixed_string = true,
				case_insensitive = true,
				include = "*.lua",
				exclude = "*.min.js",
			})
			assert.same({
				"-r",
				"-n",
				"-H",
				"-Z",
				"-F",
				"-i",
				"--include=*.lua",
				"--exclude=*.min.js",
				"foo",
				"/src",
			}, args)
		end)

		it("uses -R instead of -r when follow_links is true", function()
			local args = grep_cmd.build_args({ pattern = "f", path = ".", follow_links = true })
			assert.is_true(has_token(args, "-R"))
			assert.is_false(has_token(args, "-r"))
		end)

		it("uses -r (not -R) when follow_links is false", function()
			local args = grep_cmd.build_args({ pattern = "f", path = ".", follow_links = false })
			assert.is_true(has_token(args, "-r"))
			assert.is_false(has_token(args, "-R"))
		end)

		it("path as array appends multiple trailing path args after pattern", function()
			local args = grep_cmd.build_args({ pattern = "foo", path = { "/a", "/b", "/c" } })
			assert.equals("foo", args[#args - 3])
			assert.equals("/a", args[#args - 2])
			assert.equals("/b", args[#args - 1])
			assert.equals("/c", args[#args])
		end)

		it("path as single-element array works like path string", function()
			local args = grep_cmd.build_args({ pattern = "foo", path = { "/only" } })
			assert.equals("foo", args[#args - 1])
			assert.equals("/only", args[#args])
		end)
	end)
end)
