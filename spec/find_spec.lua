require("spec.support.awesome_mocks")

local awful = require("awful")
local gears = require("gears")

-- Use a stub backend so tests are not affected by which tool is installed.
local stub_backend = {
	command = "stub",
	build_args = function(_opts)
		return { "--stub" }
	end,
}

local find = require("continuity.tools.find")
find._set_backend(stub_backend)

-- ─── normalize ──────────────────────────────────────────────────────────────

describe("find._normalize", function()
	before_each(function()
		find._set_backend(stub_backend)
	end)

	it("converts a string to { pattern = str }", function()
		assert.same({ pattern = "foo" }, find._normalize("foo"))
	end)

	it("uses t[1] as pattern, preserves named keys", function()
		local result = find._normalize({ "foo", type = "file" })
		assert.equals("foo", result.pattern)
		assert.equals("file", result.type)
	end)

	it("t[1] wins over t.pattern", function()
		local result = find._normalize({ "bar", pattern = "ignored" })
		assert.equals("bar", result.pattern)
	end)

	it("passes fully-keyed opts through unchanged", function()
		assert.same({ pattern = "foo" }, find._normalize({ pattern = "foo" }))
	end)

	it("warns and ignores t[2] and beyond", function()
		local warned = false
		local orig_warn = gears.debug.print_warning
		gears.debug.print_warning = function()
			warned = true
		end
		find._normalize({ "foo", "extra" })
		gears.debug.print_warning = orig_warn
		assert.is_true(warned)
	end)

	it("does not leak t[1] into the returned opts table", function()
		local result = find._normalize({ "foo", type = "file" })
		assert.is_nil(result[1])
	end)
end)

-- ─── async ──────────────────────────────────────────────────────────────────

describe("find (async)", function()
	local last_argv, last_cb

	before_each(function()
		find._set_backend(stub_backend)
		last_argv = nil
		last_cb = nil
		awful.spawn.easy_async = function(argv, cb)
			last_argv = argv
			last_cb = cb
		end
	end)

	after_each(function()
		awful.spawn.easy_async = function(cmd, cb) end
	end)

	it("calls easy_async with command prepended to build_args output", function()
		find("foo", function() end)
		assert.same({ "stub", "--stub" }, last_argv)
	end)

	it("delivers lines split by newline", function()
		local results, code
		find("foo", function(r, c)
			results = r
			code = c
		end)
		last_cb("/a/b\n/c/d\n", "", "exit", 0)
		assert.same({ "/a/b", "/c/d" }, results)
		assert.equals(0, code)
	end)

	it("returns empty table when stdout is empty", function()
		local results
		find("foo", function(r)
			results = r
		end)
		last_cb("", "", "exit", 0)
		assert.same({}, results)
	end)

	it("returns empty table when stdout is only a newline", function()
		local results
		find("foo", function(r)
			results = r
		end)
		last_cb("\n", "", "exit", 0)
		assert.same({}, results)
	end)

	it("forwards non-zero exit code", function()
		local code
		find("foo", function(_, c)
			code = c
		end)
		last_cb("", "", "exit", 1)
		assert.equals(1, code)
	end)

	it("does not spawn when no backend is available", function()
		find._set_backend(nil)
		find("foo", function() end)
		assert.is_nil(last_argv)
	end)

	it("calls cb({}, 1) immediately when no backend is available", function()
		find._set_backend(nil)
		local results, code
		find("foo", function(r, c)
			results = r
			code = c
		end)
		assert.same({}, results)
		assert.equals(1, code)
	end)
end)

-- ─── stream ─────────────────────────────────────────────────────────────────

describe("find.stream", function()
	local captured_cbs

	before_each(function()
		find._set_backend(stub_backend)
		captured_cbs = nil
		gears._created = {}
		awful.spawn.with_line_callback = function(_argv, callbacks)
			captured_cbs = callbacks
			return {}
		end
	end)

	after_each(function()
		awful.spawn.with_line_callback = function(cmd, callbacks)
			return {}
		end
	end)

	it("calls with_line_callback with command prepended to build_args", function()
		local last_argv
		awful.spawn.with_line_callback = function(argv, cbs)
			last_argv = argv
			captured_cbs = cbs
			return {}
		end
		find.stream("foo", function() end)
		assert.same({ "stub", "--stub" }, last_argv)
	end)

	it("creates the timer at stream start before any lines arrive", function()
		find.stream("foo", function() end)
		assert.equals(1, #gears._created)
	end)

	it("calls timer:again() on each incoming line", function()
		find.stream("foo", function() end)
		local t = gears._created[1]
		assert.equals(0, t.again_count)
		captured_cbs.stdout("line1")
		assert.equals(1, t.again_count)
		captured_cbs.stdout("line2")
		assert.equals(2, t.again_count)
	end)

	it("does not create additional timers for more lines", function()
		find.stream("foo", function() end)
		captured_cbs.stdout("line1")
		captured_cbs.stdout("line2")
		assert.equals(1, #gears._created)
	end)

	it("flushes accumulated batch when timer fires", function()
		local batches = {}
		find.stream("foo", function(batch, _)
			if batch then
				batches[#batches + 1] = batch
			end
		end)
		captured_cbs.stdout("line1")
		captured_cbs.stdout("line2")
		gears._created[1]:fire()
		assert.equals(1, #batches)
		assert.same({ "line1", "line2" }, batches[1])
	end)

	it("resets buffer after flush so next batch is independent", function()
		local batches = {}
		find.stream("foo", function(batch, _)
			if batch then
				batches[#batches + 1] = batch
			end
		end)
		captured_cbs.stdout("a")
		gears._created[1]:fire()
		captured_cbs.stdout("b")
		gears._created[1]:fire()
		assert.same({ "a" }, batches[1])
		assert.same({ "b" }, batches[2])
	end)

	it("flushes remaining buffer on exit, then calls cb(nil, exit_code)", function()
		local calls = {}
		find.stream("foo", function(batch, code)
			calls[#calls + 1] = { batch = batch, code = code }
		end)
		captured_cbs.stdout("remaining")
		captured_cbs.exit("exit", 0)
		assert.equals(2, #calls)
		assert.same({ "remaining" }, calls[1].batch)
		assert.is_nil(calls[1].code)
		assert.is_nil(calls[2].batch)
		assert.equals(0, calls[2].code)
	end)

	it("calls cb(nil, exit_code) even when buffer is empty on exit", function()
		local terminal_called = false
		find.stream("foo", function(batch, _)
			if batch == nil then
				terminal_called = true
			end
		end)
		captured_cbs.exit("exit", 0)
		assert.is_true(terminal_called)
	end)

	it("stops timer on exit to prevent double-flush", function()
		local batch_calls = 0
		find.stream("foo", function(batch, _)
			if batch then
				batch_calls = batch_calls + 1
			end
		end)
		captured_cbs.stdout("line1")
		captured_cbs.exit("exit", 0) -- flushes buffer, stops timer
		local timer = gears._created[1]
		assert.is_true(timer.stopped)
		timer:fire() -- no-op because stopped
		assert.equals(1, batch_calls)
	end)

	it("timer callback skips cb when buffer is already empty", function()
		local batch_calls = 0
		find.stream("foo", function(batch, _)
			if batch then
				batch_calls = batch_calls + 1
			end
		end)
		captured_cbs.stdout("line1")
		-- exit flushes buffer before timer fires
		captured_cbs.exit("exit", 0)
		-- force fire on stopped timer by resetting stopped (edge-case guard test)
		gears._created[1].stopped = false
		gears._created[1]:fire()
		-- buffer was already cleared; cb must not be called again
		assert.equals(1, batch_calls)
	end)

	it("does not spawn when no backend is available", function()
		find._set_backend(nil)
		local spawned = false
		awful.spawn.with_line_callback = function()
			spawned = true
			return {}
		end
		find.stream("foo", function() end)
		assert.is_false(spawned)
	end)

	it("calls cb(nil, 1) immediately when no backend is available", function()
		find._set_backend(nil)
		local batch, code
		find.stream("foo", function(b, c)
			batch = b
			code = c
		end)
		assert.is_nil(batch)
		assert.equals(1, code)
	end)

	it("concurrent stream calls have independent buffers", function()
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
		find.stream("foo", function(b, _)
			if b then
				batches_a[#batches_a + 1] = b
			end
		end)
		find.stream("bar", function(b, _)
			if b then
				batches_b[#batches_b + 1] = b
			end
		end)
		cbs_a.stdout("from_a")
		cbs_b.stdout("from_b")
		gears._created[1]:fire()
		gears._created[2]:fire()
		assert.same({ "from_a" }, batches_a[1])
		assert.same({ "from_b" }, batches_b[1])
	end)
end)
