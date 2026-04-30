require("spec.support.awesome_mocks")
local find_cmd = require("continuity.tools.find.backends.find")

-- Helper: find a pair of adjacent tokens in an argv table.
local function has_pair(args, a, b)
	for i = 1, #args - 1 do
		if args[i] == a and args[i + 1] == b then
			return true
		end
	end
	return false
end

-- Helper: find a triple of adjacent tokens.
local function has_triple(args, a, b, c)
	for i = 1, #args - 2 do
		if args[i] == a and args[i + 1] == b and args[i + 2] == c then
			return true
		end
	end
	return false
end

describe("find backend", function()
	it("has command 'find'", function()
		assert.equals("find", find_cmd.command)
	end)

	describe("build_args", function()
		it("uses . as first token when opts.path is nil", function()
			local args = find_cmd.build_args({})
			assert.equals(".", args[1])
		end)

		it("uses opts.path as first token", function()
			local args = find_cmd.build_args({ path = "/home" })
			assert.equals("/home", args[1])
		end)

		it("adds -maxdepth <n>", function()
			local args = find_cmd.build_args({ maxdepth = 2 })
			assert.is_true(has_pair(args, "-maxdepth", "2"))
		end)

		it("maps type 'file' to -type f", function()
			assert.is_true(has_pair(find_cmd.build_args({ type = "file" }), "-type", "f"))
		end)

		it("maps type 'directory' to -type d", function()
			assert.is_true(has_pair(find_cmd.build_args({ type = "directory" }), "-type", "d"))
		end)

		it("maps type 'symlink' to -type l", function()
			assert.is_true(has_pair(find_cmd.build_args({ type = "symlink" }), "-type", "l"))
		end)

		it("maps type 'block' to -type b", function()
			assert.is_true(has_pair(find_cmd.build_args({ type = "block" }), "-type", "b"))
		end)

		it("maps type 'char' to -type c", function()
			assert.is_true(has_pair(find_cmd.build_args({ type = "char" }), "-type", "c"))
		end)

		it("maps type 'pipe' to -type p", function()
			assert.is_true(has_pair(find_cmd.build_args({ type = "pipe" }), "-type", "p"))
		end)

		it("maps type 'socket' to -type s", function()
			assert.is_true(has_pair(find_cmd.build_args({ type = "socket" }), "-type", "s"))
		end)

		it("wraps pattern in .* for -regex", function()
			local args = find_cmd.build_args({ pattern = "foo" })
			assert.is_true(has_pair(args, "-regex", ".*foo.*"))
		end)

		it("adds -name *.ext for extension", function()
			local args = find_cmd.build_args({ extension = "lua" })
			assert.is_true(has_pair(args, "-name", "*.lua"))
		end)

		it("adds -not -name .* when hidden is nil", function()
			local args = find_cmd.build_args({})
			assert.is_true(has_triple(args, "-not", "-name", ".*"))
		end)

		it("adds -not -name .* when hidden is false", function()
			local args = find_cmd.build_args({ hidden = false })
			assert.is_true(has_triple(args, "-not", "-name", ".*"))
		end)

		it("omits -not -name .* when hidden is true", function()
			local args = find_cmd.build_args({ hidden = true })
			for _, v in ipairs(args) do
				assert.not_equals("-not", v)
			end
		end)

		it("adds -exec tokens terminated by ;", function()
			local args = find_cmd.build_args({ exec = "echo {}" })
			local found = false
			for i = 1, #args - 3 do
				if args[i] == "-exec" and args[i + 1] == "echo" and args[i + 2] == "{}" and args[i + 3] == ";" then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)

		it("-not -name .* appears before -exec", function()
			local args = find_cmd.build_args({ exec = "echo {}" })
			local not_pos, exec_pos
			for i, v in ipairs(args) do
				if v == "-not" and not not_pos then
					not_pos = i
				end
				if v == "-exec" and not exec_pos then
					exec_pos = i
				end
			end
			assert.is_not_nil(not_pos)
			assert.is_not_nil(exec_pos)
			assert.is_true(not_pos < exec_pos)
		end)

		it("produces correct argv for combined opts", function()
			-- Verifies the spec-mandated token ordering for find(1):
			-- path first, flags, -not -name .* before -exec.
			-- assert.same is intentional here: the token order is the spec contract.
			local args = find_cmd.build_args({ pattern = "foo", path = "/home", maxdepth = 3 })
			assert.same({ "/home", "-maxdepth", "3", "-regex", ".*foo.*", "-not", "-name", ".*" }, args)
		end)
	end)
end)
