require("spec.support.awesome_mocks")

describe("audio.backends.pulse (sink-input parsing)", function()
	local pulse

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		pulse = require("continuity.audio.backends.pulse")
	end)

	local SINGLE_INPUT_LIST = table.concat({
		"Sink Input #263",
		"\tDriver: protocol-native.c",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 26542 /  41% / -23.56 dB,   front-right: 26542 /  41% / -23.56 dB",
		"\t        balance 0.00",
		"\tProperties:",
		'\t\tapplication.name = "spotify"',
		'\t\tmedia.name = "Spotify"',
		'\t\tapplication.process.binary = "spotify"',
	}, "\n") .. "\n"

	local MULTI_INPUT_LIST = table.concat({
		"Sink Input #263",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 26542 /  41% / -23.56 dB",
		"\tProperties:",
		'\t\tapplication.name = "spotify"',
		'\t\tmedia.name = "Spotify"',
		"Sink Input #264",
		"\tSink: 57",
		"\tMute: yes",
		"\tVolume: front-left: 65536 / 100% / 0.00 dB",
		"\tProperties:",
		'\t\tapplication.name = "firefox"',
		'\t\tmedia.name = "Firefox"',
	}, "\n") .. "\n"

	describe("find_sink_input_block", function()
		it("returns the block for a known id", function()
			local block = pulse._private.find_sink_input_block(SINGLE_INPUT_LIST, "263")
			assert.is_not_nil(block)
			assert.truthy(block:find("spotify", 1, true))
		end)

		it("returns the correct block when multiple inputs are present", function()
			local block = pulse._private.find_sink_input_block(MULTI_INPUT_LIST, "264")
			assert.is_not_nil(block)
			assert.truthy(block:find("firefox", 1, true))
			assert.is_falsy(block:find("spotify", 1, true))
		end)

		it("returns nil for unknown id", function()
			local block = pulse._private.find_sink_input_block(SINGLE_INPUT_LIST, "999")
			assert.is_nil(block)
		end)
	end)

	describe("parse_sink_input_block", function()
		it("parses level, muted=false, name, and sink into state; app_name into meta", function()
			local block = pulse._private.find_sink_input_block(SINGLE_INPUT_LIST, "263")
			local state, meta = pulse._private.parse_sink_input_block("263", block)
			assert.equals(41, state.level)
			assert.is_false(state.muted)
			assert.equals("Spotify", state.name)
			assert.equals(57, state.sink)
			assert.equals("spotify", meta.app_name)
			assert.is_nil(meta.icon_name)
		end)

		it("parses muted=true", function()
			local block = pulse._private.find_sink_input_block(MULTI_INPUT_LIST, "264")
			local state, meta = pulse._private.parse_sink_input_block("264", block)
			assert.is_true(state.muted)
			assert.equals(100, state.level)
			assert.equals("firefox", meta.app_name)
		end)

		it("returns nil name, sink, app_name, icon_name when properties are absent", function()
			local block = table.concat({
				"\tMute: no",
				"\tVolume: front-left: 32768 /  50% / -18.06 dB",
			}, "\n") .. "\n"
			local state, meta = pulse._private.parse_sink_input_block("100", block)
			assert.equals(50, state.level)
			assert.is_nil(state.name)
			assert.is_nil(state.sink)
			assert.is_false(state.muted)
			assert.is_nil(meta.app_name)
			assert.is_nil(meta.icon_name)
		end)

		it("parses icon_name from application.icon_name property", function()
			local block = table.concat({
				"\tMute: no",
				"\tVolume: front-left: 32768 /  50% / -18.06 dB",
				"\tProperties:",
				'\t\tapplication.name = "Google Chrome"',
				'\t\tapplication.icon_name = "google-chrome"',
			}, "\n") .. "\n"
			local state, meta = pulse._private.parse_sink_input_block("100", block)
			assert.equals(50, state.level)
			assert.equals("Google Chrome", meta.app_name)
			assert.equals("google-chrome", meta.icon_name)
		end)
	end)
end)

describe("audio.backends.pulse (sink-input dispatch)", function()
	local pulse, awful, wlc_cbs, easy_cmds

	local SINGLE_INPUT_LIST = table.concat({
		"Sink Input #263",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 26542 /  41% / -23.56 dB",
		"\tProperties:",
		'\t\tapplication.name = "spotify"',
		'\t\tmedia.name = "Spotify"',
	}, "\n") .. "\n"

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		easy_cmds = {}
		wlc_cbs = nil
		awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			easy_cmds[#easy_cmds + 1] = { cmd = cmd, cb = cb }
		end
		awful.spawn.with_line_callback = function(_cmd, cbs)
			wlc_cbs = cbs
			return 0
		end
		pulse = require("continuity.audio.backends.pulse")
	end)

	it("polls sink-inputs on start when inputs callbacks are provided", function()
		local added = {}
		pulse():start({
			inputs = {
				add = function(id, state)
					added[#added + 1] = { id = id, state = state }
				end,
				update = function() end,
				remove = function() end,
			},
		})
		assert.equals(1, #easy_cmds)
		local cmd_str = type(easy_cmds[1].cmd) == "table" and table.concat(easy_cmds[1].cmd, " ") or easy_cmds[1].cmd
		assert.truthy(cmd_str:find("list sink%-inputs"))
		easy_cmds[1].cb(SINGLE_INPUT_LIST, "", "", 0)
		assert.equals(1, #added)
		assert.equals("263", added[1].id)
		assert.equals(41, added[1].state.level)
	end)

	it("does not poll sink-inputs on start when inputs is nil", function()
		pulse():start({ on_sink = function() end })
		assert.equals(1, #easy_cmds)
		local cmd_str = type(easy_cmds[1].cmd) == "table" and table.concat(easy_cmds[1].cmd, " ") or easy_cmds[1].cmd
		assert.truthy(cmd_str:find("list sinks"))
	end)

	it("calls inputs.add on 'new' sink-input event", function()
		local added = {}
		pulse():start({
			inputs = {
				add = function(id, state)
					added[#added + 1] = { id = id, state = state }
				end,
				update = function() end,
				remove = function() end,
			},
		})
		easy_cmds[1].cb("", "", "", 0) -- complete startup poll (empty)
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'new' on sink-input #263")
		assert.equals(count + 1, #easy_cmds)
		easy_cmds[#easy_cmds].cb(SINGLE_INPUT_LIST, "", "", 0)
		assert.equals(1, #added)
		assert.equals("263", added[1].id)
	end)

	it("calls inputs.remove on 'remove' sink-input event without polling", function()
		local removed = {}
		pulse():start({
			inputs = {
				add = function() end,
				update = function() end,
				remove = function(id)
					removed[#removed + 1] = id
				end,
			},
		})
		easy_cmds[1].cb("", "", "", 0)
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'remove' on sink-input #263")
		assert.equals(count, #easy_cmds) -- no new poll
		assert.equals(1, #removed)
		assert.equals("263", removed[1])
	end)

	it("does not dispatch sink-input events when inputs is nil", function()
		pulse():start({ on_sink = function() end })
		easy_cmds[1].cb("", "", "", 0)
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'new' on sink-input #263")
		assert.equals(count, #easy_cmds)
	end)

	it("sink and source events still work alongside sink-input events", function()
		pulse():start({
			on_sink = function() end,
			inputs = { add = function() end, update = function() end, remove = function() end },
		})
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'change' on sink #57")
		assert.equals(count + 1, #easy_cmds)
	end)

	local VOLUME_MUTE_OUTPUT = table.concat({
		"Volume: front-left: 32768 /  50% / -18.06 dB,   front-right: 32768 /  50% / -18.06 dB",
		"        balance 0.00",
		"Mute: no",
	}, "\n") .. "\n"

	it("calls inputs.update on 'change' sink-input event", function()
		local updated = {}
		pulse():start({
			inputs = {
				add = function() end,
				update = function(id, state)
					updated[#updated + 1] = { id = id, state = state }
				end,
				remove = function() end,
			},
		})
		easy_cmds[1].cb("", "", "", 0) -- startup poll
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'change' on sink-input #263")
		assert.equals(count + 1, #easy_cmds)
		local cmd_str = type(easy_cmds[#easy_cmds].cmd) == "table" and table.concat(easy_cmds[#easy_cmds].cmd, " ")
			or easy_cmds[#easy_cmds].cmd
		assert.truthy(cmd_str:find("get%-sink%-input%-volume"))
		easy_cmds[#easy_cmds].cb(VOLUME_MUTE_OUTPUT, "", "", 0)
		assert.equals(1, #updated)
		assert.equals("263", updated[1].id)
		assert.equals(50, updated[1].state.level)
		assert.is_false(updated[1].state.muted)
	end)

	it("fires two update polls when pending_inputs is empty", function()
		local updated = {}
		pulse():start({
			inputs = {
				add = function() end,
				update = function(id, state)
					updated[#updated + 1] = { id = id, state = state }
				end,
				remove = function() end,
			},
		})
		easy_cmds[1].cb("", "", "", 0) -- startup poll
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'change' on sink-input #263")
		wlc_cbs.stdout("Event 'change' on sink-input #263")
		assert.equals(count + 2, #easy_cmds)
	end)
end)

describe("audio.backends.pulse (sink-input control)", function()
	local pulse, awful, easy_cmds, wlc_cbs

	local VOLUME_MUTE_OUTPUT = table.concat({
		"Volume: front-left: 32768 /  50% / -18.06 dB,   front-right: 32768 /  50% / -18.06 dB",
		"        balance 0.00",
		"Mute: no",
	}, "\n") .. "\n"

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		easy_cmds = {}
		wlc_cbs = nil
		awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			easy_cmds[#easy_cmds + 1] = { cmd = cmd, cb = cb }
		end
		awful.spawn.with_line_callback = function(_cmd, cbs)
			wlc_cbs = cbs
			return 0
		end
		pulse = require("continuity.audio.backends.pulse")
	end)

	local function fire(n, stdout)
		easy_cmds[n].cb(stdout or "", "", "", 0)
	end

	it("adjust_input_perc issues set-sink-input-volume with delta and calls cb", function()
		local backend = pulse()
		backend:start({})
		local result = nil
		backend:adjust_input_perc("263", 10, function(level, muted)
			result = { level = level, muted = muted }
		end)
		assert.equals(1, #easy_cmds)
		local cmd_str = table.concat(easy_cmds[1].cmd, " ")
		assert.truthy(cmd_str:find("set%-sink%-input%-volume"))
		assert.truthy(cmd_str:find("263"))
		assert.truthy(cmd_str:find("%+10%%"))
		fire(1, "") -- set completes
		assert.equals(2, #easy_cmds) -- post-set query
		local q_str = table.concat(easy_cmds[2].cmd, " ")
		assert.truthy(q_str:find("get%-sink%-input%-volume"))
		fire(2, VOLUME_MUTE_OUTPUT)
		assert.is_not_nil(result)
		assert.equals(50, result.level)
		assert.is_false(result.muted)
	end)

	it("adjust_input_perc increments pending_inputs so the next change event is suppressed", function()
		local updated = {}
		local backend = pulse()
		backend:start({
			inputs = {
				add = function() end,
				update = function(id, state)
					updated[#updated + 1] = { id = id, state = state }
				end,
				remove = function() end,
			},
		})
		easy_cmds[1].cb("", "", "", 0) -- startup poll
		backend:adjust_input_perc("263", 5, function() end)
		fire(#easy_cmds, "") -- set completes, query issued
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'change' on sink-input #263")
		assert.equals(count, #easy_cmds) -- suppressed
		wlc_cbs.stdout("Event 'change' on sink-input #263")
		assert.equals(count + 1, #easy_cmds) -- now fires
	end)

	it("set_input_perc issues set-sink-input-volume with absolute percent", function()
		local backend = pulse()
		backend:start({})
		backend:set_input_perc("263", 75, function() end)
		local cmd_str = table.concat(easy_cmds[1].cmd, " ")
		assert.truthy(cmd_str:find("set%-sink%-input%-volume"))
		assert.truthy(cmd_str:find("75%%"))
	end)

	it("toggle_input issues set-sink-input-mute with toggle", function()
		local backend = pulse()
		backend:start({})
		backend:toggle_input("263", function() end)
		local cmd_str = table.concat(easy_cmds[1].cmd, " ")
		assert.truthy(cmd_str:find("set%-sink%-input%-mute"))
		assert.truthy(cmd_str:find("toggle"))
	end)
end)
