require("spec.support.awesome_mocks")
local rg = require("continuity.tools.grep.backends.rg")

local function has_token(args, t)
	for _, v in ipairs(args) do
		if v == t then
			return true
		end
	end
	return false
end

local function has_pair(args, a, b)
	for i = 1, #args - 1 do
		if args[i] == a and args[i + 1] == b then
			return true
		end
	end
	return false
end

describe("rg backend", function()
	it("has command 'rg'", function()
		assert.equals("rg", rg.command)
	end)

	describe("build_args", function()
		it("always starts with --with-filename --no-heading --line-number --null", function()
			local args = rg.build_args({ pattern = "foo", path = "/home" })
			assert.equals("--with-filename", args[1])
			assert.equals("--no-heading", args[2])
			assert.equals("--line-number", args[3])
			assert.equals("--null", args[4])
		end)

		it("appends pattern then path as the final two tokens", function()
			local args = rg.build_args({ pattern = "foo", path = "/home" })
			assert.equals("foo", args[#args - 1])
			assert.equals("/home", args[#args])
		end)

		it("adds -F for fixed_string", function()
			assert.is_true(has_token(rg.build_args({ pattern = "f", path = ".", fixed_string = true }), "-F"))
		end)

		it("omits -F when fixed_string is false", function()
			assert.is_false(has_token(rg.build_args({ pattern = "f", path = ".", fixed_string = false }), "-F"))
		end)

		it("adds -i for case_insensitive", function()
			assert.is_true(has_token(rg.build_args({ pattern = "f", path = ".", case_insensitive = true }), "-i"))
		end)

		it("omits -i when case_insensitive is false", function()
			assert.is_false(has_token(rg.build_args({ pattern = "f", path = ".", case_insensitive = false }), "-i"))
		end)

		it("adds --max-depth N for max_depth", function()
			assert.is_true(has_pair(rg.build_args({ pattern = "f", path = ".", max_depth = 3 }), "--max-depth", "3"))
		end)

		it("adds --glob INCLUDE for include", function()
			assert.is_true(has_pair(rg.build_args({ pattern = "f", path = ".", include = "*.lua" }), "--glob", "*.lua"))
		end)

		it("adds --glob !EXCLUDE for exclude", function()
			assert.is_true(
				has_pair(rg.build_args({ pattern = "f", path = ".", exclude = "*.min.js" }), "--glob", "!*.min.js")
			)
		end)

		it("adds --type TYPE for type", function()
			assert.is_true(has_pair(rg.build_args({ pattern = "f", path = ".", type = "lua" }), "--type", "lua"))
		end)

		it("produces correct full argv for combined opts", function()
			local args = rg.build_args({
				pattern = "foo",
				path = "/src",
				fixed_string = true,
				case_insensitive = true,
				max_depth = 2,
				include = "*.lua",
				exclude = "*.min.js",
				type = "lua",
			})
			assert.same({
				"--with-filename",
				"--no-heading",
				"--line-number",
				"--null",
				"-F",
				"-i",
				"--max-depth",
				"2",
				"--glob",
				"*.lua",
				"--glob",
				"!*.min.js",
				"--type",
				"lua",
				"foo",
				"/src",
			}, args)
		end)

		it("adds -L for follow_links", function()
			assert.is_true(has_token(rg.build_args({ pattern = "f", path = ".", follow_links = true }), "-L"))
		end)

		it("omits -L when follow_links is false", function()
			assert.is_false(has_token(rg.build_args({ pattern = "f", path = ".", follow_links = false }), "-L"))
		end)

		it("path as array appends multiple trailing path args after pattern", function()
			local args = rg.build_args({ pattern = "foo", path = { "/a", "/b", "/c" } })
			assert.equals("foo", args[#args - 3])
			assert.equals("/a", args[#args - 2])
			assert.equals("/b", args[#args - 1])
			assert.equals("/c", args[#args])
		end)

		it("path as single-element array works like path string", function()
			local args = rg.build_args({ pattern = "foo", path = { "/only" } })
			assert.equals("foo", args[#args - 1])
			assert.equals("/only", args[#args])
		end)
	end)
end)
