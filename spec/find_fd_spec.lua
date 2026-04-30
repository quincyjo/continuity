require("spec.support.awesome_mocks")
local fd = require("continuity.tools.find.backends.fd")

describe("fd backend", function()
	it("has command 'fd'", function()
		assert.equals("fd", fd.command)
	end)

	describe("build_args", function()
		it("returns empty table for empty opts", function()
			assert.same({}, fd.build_args({}))
		end)

		it("adds --regex for pattern", function()
			assert.same({ "--regex", "foo" }, fd.build_args({ pattern = "foo" }))
		end)

		it("adds --max-depth for maxdepth", function()
			assert.same({ "--max-depth", "3" }, fd.build_args({ maxdepth = 3 }))
		end)

		it("maps type 'file' to --type f", function()
			assert.same({ "--type", "f" }, fd.build_args({ type = "file" }))
		end)

		it("maps type 'directory' to --type d", function()
			assert.same({ "--type", "d" }, fd.build_args({ type = "directory" }))
		end)

		it("maps type 'symlink' to --type l", function()
			assert.same({ "--type", "l" }, fd.build_args({ type = "symlink" }))
		end)

		it("maps type 'block' to --type b", function()
			assert.same({ "--type", "b" }, fd.build_args({ type = "block" }))
		end)

		it("maps type 'char' to --type c", function()
			assert.same({ "--type", "c" }, fd.build_args({ type = "char" }))
		end)

		it("maps type 'pipe' to --type p", function()
			assert.same({ "--type", "p" }, fd.build_args({ type = "pipe" }))
		end)

		it("maps type 'socket' to --type s", function()
			assert.same({ "--type", "s" }, fd.build_args({ type = "socket" }))
		end)

		it("adds --extension for extension", function()
			assert.same({ "--extension", "lua" }, fd.build_args({ extension = "lua" }))
		end)

		it("adds --hidden when hidden is true", function()
			assert.same({ "--hidden" }, fd.build_args({ hidden = true }))
		end)

		it("omits --hidden when hidden is false", function()
			assert.same({}, fd.build_args({ hidden = false }))
		end)

		it("omits --hidden when hidden is nil", function()
			assert.same({}, fd.build_args({ hidden = nil }))
		end)

		it("splits exec string into --exec tokens followed by ;", function()
			assert.same({ "--exec", "echo", "{}", ";" }, fd.build_args({ exec = "echo {}" }))
		end)

		it("places exec terminator ; before path", function()
			local args = fd.build_args({ exec = "echo {}", path = "/home" })
			local semi_pos, path_pos
			for i, v in ipairs(args) do
				if v == ";" and not semi_pos then
					semi_pos = i
				end
				if v == "/home" and not path_pos then
					path_pos = i
				end
			end
			assert.is_not_nil(semi_pos)
			assert.is_not_nil(path_pos)
			assert.is_true(semi_pos < path_pos)
		end)

		it("appends path as the last token", function()
			local args = fd.build_args({ path = "/home" })
			assert.equals("/home", args[#args])
		end)

		it("puts flags before pattern before path", function()
			local args = fd.build_args({ maxdepth = 3, pattern = "%.lua$", path = "/home" })
			assert.same({ "--max-depth", "3", "--regex", "%.lua$", "/home" }, args)
		end)
	end)
end)
