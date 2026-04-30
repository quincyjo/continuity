require("spec.support.awesome_mocks")

local awful = require("awful")
local gears = require("gears")

local stub_backend = {
	command = "stub",
	build_args = function(_opts)
		return { "--stub" }
	end,
}

local grep = require("continuity.tools.grep")
grep._set_backend(stub_backend)

-- ─── normalize ───────────────────────────────────────────────────────────────

describe("grep._normalize", function()
	before_each(function()
		grep._set_backend(stub_backend)
	end)

	it("passes fully-keyed opts through unchanged", function()
		assert.same({ pattern = "foo", path = "/home" }, grep._normalize({ pattern = "foo", path = "/home" }))
	end)

	it("uses t[1] as pattern and t[2] as path", function()
		local result = grep._normalize({ "foo", "/home" })
		assert.equals("foo", result.pattern)
		assert.equals("/home", result.path)
	end)

	it("t[1] wins over opts.pattern when both present", function()
		local result = grep._normalize({ "bar", "/home", pattern = "ignored" })
		assert.equals("bar", result.pattern)
	end)

	it("positional keys do not leak into result", function()
		local result = grep._normalize({ "foo", "/home" })
		assert.is_nil(result[1])
		assert.is_nil(result[2])
	end)

	it("named keys are preserved alongside positional", function()
		local result = grep._normalize({ "foo", "/home", fixed_string = true })
		assert.equals("foo", result.pattern)
		assert.equals("/home", result.path)
		assert.is_true(result.fixed_string)
	end)

	it("warns and ignores t[3] and beyond", function()
		local warned = false
		local orig_warn = gears.debug.print_warning
		gears.debug.print_warning = function()
			warned = true
		end
		grep._normalize({ "foo", "/home", "extra" })
		gears.debug.print_warning = orig_warn
		assert.is_true(warned)
	end)

	it("does not warn when only t[1] and t[2] are present", function()
		local warned = false
		local orig_warn = gears.debug.print_warning
		gears.debug.print_warning = function()
			warned = true
		end
		grep._normalize({ "foo", "/home" })
		gears.debug.print_warning = orig_warn
		assert.is_false(warned)
	end)
end)

-- ─── parse_line ──────────────────────────────────────────────────────────────

describe("grep._parse_line", function()
	local sep = string.char(9) -- TAB: what arrives after tr translates NUL

	it("parses filepath, line_number, and text", function()
		local intern = {}
		local result = grep._parse_line("/path/to/file" .. sep .. "42:matched content", intern)
		assert.equals("/path/to/file", result.filepath)
		assert.equals(42, result.line_number)
		assert.equals("matched content", result.text)
	end)

	it("returns nil for a line with no TAB separator", function()
		local intern = {}
		assert.is_nil(grep._parse_line("/path/to/file:42:content", intern))
	end)

	it("handles colons in filepath correctly", function()
		local intern = {}
		local result = grep._parse_line("/path/123:foo/file" .. sep .. "7:text", intern)
		assert.equals("/path/123:foo/file", result.filepath)
		assert.equals(7, result.line_number)
		assert.equals("text", result.text)
	end)

	it("handles colons in text correctly", function()
		local intern = {}
		local result = grep._parse_line("/file" .. sep .. "1:key:value:extra", intern)
		assert.equals("key:value:extra", result.text)
	end)

	it("interns filepath — same table instance for same path", function()
		local intern = {}
		local r1 = grep._parse_line("/file" .. sep .. "1:foo", intern)
		local r2 = grep._parse_line("/file" .. sep .. "2:bar", intern)
		assert.is_true(r1.filepath == r2.filepath)
	end)
end)

-- ─── async ───────────────────────────────────────────────────────────────────

describe("grep (async)", function()
	local sep = string.char(9) -- TAB: what arrives after tr translates NUL
	local last_argv, last_cb

	before_each(function()
		grep._set_backend(stub_backend)
		last_argv = nil
		last_cb = nil
		awful.spawn.easy_async = function(argv, cb)
			last_argv = argv
			last_cb = cb
		end
	end)

	after_each(function()
		awful.spawn.easy_async = function(_cmd, _cb) end
	end)

	it("calls easy_async with backend command inside NUL->TAB shell wrapper", function()
		grep({ pattern = "foo", path = "." }, function() end)
		assert.equals("sh", last_argv[1])
		assert.equals("-c", last_argv[2])
		assert.equals("sh", last_argv[4]) -- $0 for the inner shell
		assert.equals("stub", last_argv[5])
		assert.equals("--stub", last_argv[6])
	end)

	it("parses results from stdout", function()
		local results, code
		grep({ pattern = "foo", path = "." }, function(r, c)
			results = r
			code = c
		end)
		last_cb("/a/b" .. sep .. "1:hello\n/c/d" .. sep .. "2:world\n", "", "exit", 0)
		assert.equals(2, #results)
		assert.equals("/a/b", results[1].filepath)
		assert.equals(1, results[1].line_number)
		assert.equals("hello", results[1].text)
		assert.equals("/c/d", results[2].filepath)
		assert.equals(2, results[2].line_number)
		assert.equals("world", results[2].text)
		assert.equals(0, code)
	end)

	it("returns empty table when stdout is empty", function()
		local results
		grep({ pattern = "foo", path = "." }, function(r)
			results = r
		end)
		last_cb("", "", "exit", 0)
		assert.same({}, results)
	end)

	it("skips unparseable lines silently", function()
		local results
		grep({ pattern = "foo", path = "." }, function(r)
			results = r
		end)
		last_cb("not-a-valid-line\n/a/b" .. sep .. "1:good\n", "", "exit", 0)
		assert.equals(1, #results)
		assert.equals("/a/b", results[1].filepath)
	end)

	it("forwards non-zero exit code", function()
		local code
		grep({ pattern = "foo", path = "." }, function(_, c)
			code = c
		end)
		last_cb("", "", "exit", 1)
		assert.equals(1, code)
	end)

	it("interns filepath — same instance across results", function()
		local results
		grep({ pattern = "foo", path = "." }, function(r)
			results = r
		end)
		last_cb("/a/b" .. sep .. "1:x\n/a/b" .. sep .. "2:y\n", "", "exit", 0)
		assert.is_true(results[1].filepath == results[2].filepath)
	end)

	it("does not spawn when no backend is available", function()
		grep._set_backend(nil)
		grep({ pattern = "foo", path = "." }, function() end)
		assert.is_nil(last_argv)
	end)

	it("calls cb({}, 1) immediately when no backend is available", function()
		grep._set_backend(nil)
		local results, code
		grep({ pattern = "foo", path = "." }, function(r, c)
			results = r
			code = c
		end)
		assert.same({}, results)
		assert.equals(1, code)
	end)
end)

-- ─── stream ──────────────────────────────────────────────────────────────────

describe("grep.stream", function()
	local sep = string.char(9) -- TAB: what arrives after tr translates NUL
	local captured_cbs

	before_each(function()
		grep._set_backend(stub_backend)
		captured_cbs = nil
		gears._created = {}
		awful.spawn.with_line_callback = function(_argv, callbacks)
			captured_cbs = callbacks
			return {}
		end
	end)

	after_each(function()
		awful.spawn.with_line_callback = function(_cmd, _callbacks)
			return {}
		end
	end)

	it("calls with_line_callback with backend command inside NUL->TAB shell wrapper", function()
		local last_argv
		awful.spawn.with_line_callback = function(argv, cbs)
			last_argv = argv
			captured_cbs = cbs
			return {}
		end
		grep.stream({ pattern = "foo", path = "." }, function() end)
		assert.equals("sh", last_argv[1])
		assert.equals("-c", last_argv[2])
		assert.equals("sh", last_argv[4])
		assert.equals("stub", last_argv[5])
		assert.equals("--stub", last_argv[6])
	end)

	it("creates the timer at stream start before any lines arrive", function()
		grep.stream({ pattern = "foo", path = "." }, function() end)
		assert.equals(1, #gears._created)
	end)

	it("calls timer:again() on each valid incoming line", function()
		grep.stream({ pattern = "foo", path = "." }, function() end)
		local t = gears._created[1]
		assert.equals(0, t.again_count)
		captured_cbs.stdout("/f" .. sep .. "1:a")
		assert.equals(1, t.again_count)
		captured_cbs.stdout("/f" .. sep .. "2:b")
		assert.equals(2, t.again_count)
	end)

	it("does not call timer:again() for unparseable lines", function()
		grep.stream({ pattern = "foo", path = "." }, function() end)
		local t = gears._created[1]
		captured_cbs.stdout("not-valid")
		assert.equals(0, t.again_count)
	end)

	it("flushes accumulated batch when timer fires", function()
		local batches = {}
		grep.stream({ pattern = "foo", path = "." }, function(batch, _)
			if batch then
				batches[#batches + 1] = batch
			end
		end)
		captured_cbs.stdout("/f" .. sep .. "1:hello")
		captured_cbs.stdout("/f" .. sep .. "2:world")
		gears._created[1]:fire()
		assert.equals(1, #batches)
		assert.equals(2, #batches[1])
		assert.equals("hello", batches[1][1].text)
		assert.equals("world", batches[1][2].text)
	end)

	it("resets buffer after flush so next batch is independent", function()
		local batches = {}
		grep.stream({ pattern = "foo", path = "." }, function(batch, _)
			if batch then
				batches[#batches + 1] = batch
			end
		end)
		captured_cbs.stdout("/f" .. sep .. "1:a")
		gears._created[1]:fire()
		captured_cbs.stdout("/f" .. sep .. "2:b")
		gears._created[1]:fire()
		assert.equals(1, #batches[1])
		assert.equals(1, #batches[2])
		assert.equals("a", batches[1][1].text)
		assert.equals("b", batches[2][1].text)
	end)

	it("flushes remaining buffer on exit, then calls cb(nil, exit_code)", function()
		local calls = {}
		grep.stream({ pattern = "foo", path = "." }, function(batch, code)
			calls[#calls + 1] = { batch = batch, code = code }
		end)
		captured_cbs.stdout("/f" .. sep .. "1:remaining")
		captured_cbs.exit("exit", 0)
		assert.equals(2, #calls)
		assert.equals("remaining", calls[1].batch[1].text)
		assert.is_nil(calls[1].code)
		assert.is_nil(calls[2].batch)
		assert.equals(0, calls[2].code)
	end)

	it("calls cb(nil, exit_code) even when buffer is empty on exit", function()
		local terminal_called = false
		grep.stream({ pattern = "foo", path = "." }, function(batch, _)
			if batch == nil then
				terminal_called = true
			end
		end)
		captured_cbs.exit("exit", 0)
		assert.is_true(terminal_called)
	end)

	it("stops timer on exit to prevent double-flush", function()
		local batch_calls = 0
		grep.stream({ pattern = "foo", path = "." }, function(batch, _)
			if batch then
				batch_calls = batch_calls + 1
			end
		end)
		captured_cbs.stdout("/f" .. sep .. "1:x")
		captured_cbs.exit("exit", 0)
		local timer = gears._created[1]
		assert.is_true(timer.stopped)
		timer:fire()
		assert.equals(1, batch_calls)
	end)

	it("timer callback skips cb when buffer is already empty", function()
		local batch_calls = 0
		grep.stream({ pattern = "foo", path = "." }, function(batch, _)
			if batch then
				batch_calls = batch_calls + 1
			end
		end)
		captured_cbs.stdout("/f" .. sep .. "1:x")
		-- exit flushes buffer before timer fires
		captured_cbs.exit("exit", 0)
		-- force fire on stopped timer by resetting stopped (edge-case guard test)
		gears._created[1].stopped = false
		gears._created[1]:fire()
		-- buffer was already cleared; cb must not be called again
		assert.equals(1, batch_calls)
	end)

	it("interns filepath across batches within the same stream", function()
		local all_results = {}
		grep.stream({ pattern = "foo", path = "." }, function(batch, _)
			if batch then
				for _, r in ipairs(batch) do
					all_results[#all_results + 1] = r
				end
			end
		end)
		captured_cbs.stdout("/f" .. sep .. "1:a")
		gears._created[1]:fire()
		captured_cbs.stdout("/f" .. sep .. "2:b")
		gears._created[1]:fire()
		assert.equals(2, #all_results)
		assert.is_true(all_results[1].filepath == all_results[2].filepath)
	end)

	it("does not spawn when no backend is available", function()
		grep._set_backend(nil)
		local spawned = false
		awful.spawn.with_line_callback = function()
			spawned = true
			return {}
		end
		grep.stream({ pattern = "foo", path = "." }, function() end)
		assert.is_false(spawned)
	end)

	it("calls cb(nil, 1) immediately when no backend is available", function()
		grep._set_backend(nil)
		local batch, code
		grep.stream({ pattern = "foo", path = "." }, function(b, c)
			batch = b
			code = c
		end)
		assert.is_nil(batch)
		assert.equals(1, code)
	end)

	it("concurrent stream calls have independent buffers and intern tables", function()
		local batches_a, batches_b = {}, {}
		local cbs_a, cbs_b
		awful.spawn.with_line_callback = function(_argv, callbacks)
			if not cbs_a then
				cbs_a = callbacks
			else
				cbs_b = callbacks
			end
			return {}
		end
		grep.stream({ pattern = "a", path = "." }, function(b, _)
			if b then
				batches_a[#batches_a + 1] = b
			end
		end)
		grep.stream({ pattern = "b", path = "." }, function(b, _)
			if b then
				batches_b[#batches_b + 1] = b
			end
		end)
		cbs_a.stdout("/fa" .. sep .. "1:from_a")
		cbs_b.stdout("/fb" .. sep .. "1:from_b")
		gears._created[1]:fire()
		gears._created[2]:fire()
		assert.equals("from_a", batches_a[1][1].text)
		assert.equals("from_b", batches_b[1][1].text)
	end)
end)
