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
			local state, meta = pulse._private.parse_sink_input_block(block)
			assert.equals(41, state.level)
			assert.is_false(state.muted)
			assert.equals("Spotify", state.name)
			assert.equals(57, state.sink)
			assert.equals("spotify", meta.app_name)
			assert.is_nil(meta.icon_name)
		end)

		it("parses muted=true", function()
			local block = pulse._private.find_sink_input_block(MULTI_INPUT_LIST, "264")
			local state, meta = pulse._private.parse_sink_input_block(block)
			assert.is_true(state.muted)
			assert.equals(100, state.level)
			assert.equals("firefox", meta.app_name)
		end)

		it("returns nil name, sink, app_name, icon_name when properties are absent", function()
			local block = table.concat({
				"\tMute: no",
				"\tVolume: front-left: 32768 /  50% / -18.06 dB",
			}, "\n") .. "\n"
			local state, meta = pulse._private.parse_sink_input_block(block)
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
			local state, meta = pulse._private.parse_sink_input_block(block)
			assert.equals(50, state.level)
			assert.equals("Google Chrome", meta.app_name)
			assert.equals("google-chrome", meta.icon_name)
		end)
	end)

	describe("parse_all_sink_inputs_json", function()
		local SINGLE_INPUT_JSON =
			'[{"index":263,"sink":57,"mute":false,"volume":{"front-left":{"value":26542,"value_percent":"41%","db":"-23.56 dB"}},"properties":{"application.name":"spotify","media.name":"Spotify"}}]' -- luacheck: ignore

		local MULTI_INPUT_JSON =
			'[{"index":263,"sink":57,"mute":false,"volume":{"front-left":{"value":26542,"value_percent":"41%","db":"-23.56 dB"}},"properties":{"application.name":"spotify","media.name":"Spotify"}},{"index":264,"sink":57,"mute":true,"volume":{"front-left":{"value":65536,"value_percent":"100%","db":"0.00 dB"}},"properties":{"application.name":"firefox","media.name":"Firefox"}}]' -- luacheck: ignore

		it("returns one entry for a single input", function()
			local entries = pulse._private.parse_all_sink_inputs_json(SINGLE_INPUT_JSON)
			assert.equals(1, #entries)
		end)

		it("entry id is the numeric index string", function()
			local entries = pulse._private.parse_all_sink_inputs_json(SINGLE_INPUT_JSON)
			assert.equals("263", entries[1].id)
		end)

		it("entry state has correct level, muted, sink, and name", function()
			local entries = pulse._private.parse_all_sink_inputs_json(SINGLE_INPUT_JSON)
			local s = entries[1].state
			assert.equals(41, s.level)
			assert.is_false(s.muted)
			assert.equals(57, s.sink)
			assert.equals("Spotify", s.name)
		end)

		it("entry meta has correct app_name", function()
			local entries = pulse._private.parse_all_sink_inputs_json(SINGLE_INPUT_JSON)
			assert.equals("spotify", entries[1].meta.app_name)
			assert.is_nil(entries[1].meta.icon_name)
		end)

		it("returns one entry per input when multiple inputs are present", function()
			local entries = pulse._private.parse_all_sink_inputs_json(MULTI_INPUT_JSON)
			assert.equals(2, #entries)
		end)

		it("assigns correct ids and state for multiple inputs", function()
			local entries = pulse._private.parse_all_sink_inputs_json(MULTI_INPUT_JSON)
			local by_id = {}
			for _, e in ipairs(entries) do
				by_id[e.id] = e
			end
			assert.equals("spotify", by_id["263"].meta.app_name)
			assert.is_false(by_id["263"].state.muted)
			assert.equals("firefox", by_id["264"].meta.app_name)
			assert.is_true(by_id["264"].state.muted)
			assert.equals(100, by_id["264"].state.level)
		end)

		it("returns empty table for invalid JSON", function()
			local entries = pulse._private.parse_all_sink_inputs_json("not-json")
			assert.equals(0, #entries)
		end)

		it("parses icon_name from application.icon_name property", function()
			local input =
				'[{"index":100,"sink":57,"mute":false,"volume":{"front-left":{"value":32768,"value_percent":"50%","db":"-18.06 dB"}},"properties":{"application.name":"Google Chrome","application.icon_name":"google-chrome"}}]' -- luacheck: ignore
			local entries = pulse._private.parse_all_sink_inputs_json(input)
			assert.equals("Google Chrome", entries[1].meta.app_name)
			assert.equals("google-chrome", entries[1].meta.icon_name)
		end)
	end)

	describe("parse_sink_input_by_index_json", function()
		local MULTI_INPUT_JSON =
			'[{"index":263,"sink":57,"mute":false,"volume":{"front-left":{"value":26542,"value_percent":"41%","db":"-23.56 dB"}},"properties":{"application.name":"spotify","media.name":"Spotify"}},{"index":264,"sink":57,"mute":true,"volume":{"front-left":{"value":65536,"value_percent":"100%","db":"0.00 dB"}},"properties":{"application.name":"firefox","media.name":"Firefox"}}]' -- luacheck: ignore

		it("returns state and meta for a known id", function()
			local state, meta = pulse._private.parse_sink_input_by_index_json(MULTI_INPUT_JSON, "263")
			assert.is_not_nil(state)
			assert.equals(41, state.level)
			assert.is_false(state.muted)
			assert.equals(57, state.sink)
			assert.equals("Spotify", state.name)
			assert.equals("spotify", meta.app_name)
		end)

		it("returns the correct entry when multiple inputs exist", function()
			local state, meta = pulse._private.parse_sink_input_by_index_json(MULTI_INPUT_JSON, "264")
			assert.is_not_nil(state)
			assert.is_true(state.muted)
			assert.equals(100, state.level)
			assert.equals("firefox", meta.app_name)
		end)

		it("returns nil, nil for an unknown id", function()
			local state, meta = pulse._private.parse_sink_input_by_index_json(MULTI_INPUT_JSON, "999")
			assert.is_nil(state)
			assert.is_nil(meta)
		end)

		it("returns nil, nil for invalid JSON", function()
			local state, meta = pulse._private.parse_sink_input_by_index_json("not-json", "263")
			assert.is_nil(state)
			assert.is_nil(meta)
		end)

		it("parses icon_name from application.icon_name property", function()
			local input =
				'[{"index":100,"sink":57,"mute":false,"volume":{"front-left":{"value":32768,"value_percent":"50%","db":"-18.06 dB"}},"properties":{"application.name":"Google Chrome","application.icon_name":"google-chrome"}}]' -- luacheck: ignore
			local state, meta = pulse._private.parse_sink_input_by_index_json(input, "100")
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
		package.loaded["continuity.util.json"] = nil
		package.loaded["continuity.util.app_icon"] = {
			by_icon_name = function(_, cb)
				cb(nil)
			end,
			by_app_name = function(_, cb)
				cb(nil)
			end,
		}
		local saved_json = package.loaded["json"]
		package.loaded["json"] = nil
		package.preload["json"] = function()
			error("disabled")
		end -- luacheck: ignore
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
		package.preload["json"] = nil
		package.loaded["json"] = saved_json
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
		pulse():start({ sinks = { add = function() end, update = function() end, remove = function() end } })
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
		local sh = { add = function() end, update = function() end, remove = function() end }
		pulse():start({ sinks = sh })
		easy_cmds[1].cb("", "", "", 0)
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'new' on sink-input #263")
		assert.equals(count, #easy_cmds)
	end)

	it("sink and source events still work alongside sink-input events", function()
		pulse():start({
			sinks = { add = function() end, update = function() end, remove = function() end },
			inputs = { add = function() end, update = function() end, remove = function() end },
		})
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'change' on sink #57")
		assert.equals(count + 1, #easy_cmds)
	end)

	local INPUT_POLL_OUTPUT = table.concat({
		"Sink Input #263",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 32768 /  50% / -18.06 dB",
		"\tProperties:",
		'\t\tapplication.name = "spotify"',
		'\t\tmedia.name = "Spotify"',
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
		assert.truthy(cmd_str:find("list sink%-inputs"))
		easy_cmds[#easy_cmds].cb(INPUT_POLL_OUTPUT, "", "", 0)
		assert.equals(1, #updated)
		assert.equals("263", updated[1].id)
		assert.equals(50, updated[1].state.level)
		assert.is_false(updated[1].state.muted)
		assert.equals("Spotify", updated[1].state.name)
		assert.equals(57, updated[1].state.sink)
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

	local INPUT_POLL_OUTPUT = table.concat({
		"Sink Input #263",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 32768 /  50% / -18.06 dB",
		"\tProperties:",
		'\t\tapplication.name = "spotify"',
		'\t\tmedia.name = "Spotify"',
	}, "\n") .. "\n"

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		package.loaded["continuity.util.json"] = nil
		package.loaded["continuity.util.app_icon"] = {
			by_icon_name = function(_, cb)
				cb(nil)
			end,
			by_app_name = function(_, cb)
				cb(nil)
			end,
		}
		local saved_json = package.loaded["json"]
		package.loaded["json"] = nil
		package.preload["json"] = function()
			error("disabled")
		end -- luacheck: ignore
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
		package.preload["json"] = nil
		package.loaded["json"] = saved_json
	end)

	local function fire(n, stdout)
		easy_cmds[n].cb(stdout or "", "", "", 0)
	end

	it("api.sink_input.adjust_perc issues set-sink-input-volume with delta and calls cb", function()
		local backend = pulse()
		backend:start({})
		local result = nil
		backend.api.sink_input.adjust_perc("263", 10, function(level, muted)
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
		assert.truthy(q_str:find("list sink%-inputs"))
		fire(2, INPUT_POLL_OUTPUT)
		assert.is_not_nil(result)
		assert.equals(50, result.level)
		assert.is_false(result.muted)
	end)

	it("api.sink_input.adjust_perc increments pending_inputs so the next change event is suppressed", function()
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
		backend.api.sink_input.adjust_perc("263", 5, function() end)
		fire(#easy_cmds, "") -- set completes, query issued
		local count = #easy_cmds
		wlc_cbs.stdout("Event 'change' on sink-input #263")
		assert.equals(count, #easy_cmds) -- suppressed
		wlc_cbs.stdout("Event 'change' on sink-input #263")
		assert.equals(count + 1, #easy_cmds) -- now fires
	end)

	it("api.sink_input.set_perc issues set-sink-input-volume with absolute percent", function()
		local backend = pulse()
		backend:start({})
		backend.api.sink_input.set_perc("263", 75, function() end)
		local cmd_str = table.concat(easy_cmds[1].cmd, " ")
		assert.truthy(cmd_str:find("set%-sink%-input%-volume"))
		assert.truthy(cmd_str:find("75%%"))
	end)

	it("api.sink_input.toggle issues set-sink-input-mute with toggle", function()
		local backend = pulse()
		backend:start({})
		backend.api.sink_input.toggle("263", function() end)
		local cmd_str = table.concat(easy_cmds[1].cmd, " ")
		assert.truthy(cmd_str:find("set%-sink%-input%-mute"))
		assert.truthy(cmd_str:find("toggle"))
	end)
end)

describe("audio.backends.pulse (register_input icon resolution)", function()
	local pulse, awful, easy_cmds, app_icon_mock

	local INPUT_WITH_ICON_NAME = table.concat({
		"Sink Input #100",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 32768 /  50% / -18.06 dB",
		"\tProperties:",
		'\t\tapplication.name = "Google Chrome"',
		'\t\tapplication.icon_name = "google-chrome"',
		'\t\tmedia.name = "Google Chrome"',
	}, "\n") .. "\n"

	local INPUT_WITH_APP_NAME_ONLY = table.concat({
		"Sink Input #101",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 32768 /  50% / -18.06 dB",
		"\tProperties:",
		'\t\tapplication.name = "spotify"',
		'\t\tmedia.name = "Spotify"',
	}, "\n") .. "\n"

	local INPUT_NO_META = table.concat({
		"Sink Input #102",
		"\tSink: 57",
		"\tMute: no",
		"\tVolume: front-left: 32768 /  50% / -18.06 dB",
	}, "\n") .. "\n"

	before_each(function()
		package.loaded["continuity.audio.backends.pulse"] = nil
		package.loaded["continuity.util.json"] = nil
		app_icon_mock = {
			by_icon_name_calls = {},
			by_app_name_calls = {},
			by_icon_name = function(name, cb)
				app_icon_mock.by_icon_name_calls[#app_icon_mock.by_icon_name_calls + 1] = { name = name, cb = cb }
			end,
			by_app_name = function(name, cb)
				app_icon_mock.by_app_name_calls[#app_icon_mock.by_app_name_calls + 1] = { name = name, cb = cb }
			end,
		}
		package.loaded["continuity.util.app_icon"] = app_icon_mock
		local saved_json = package.loaded["json"]
		package.loaded["json"] = nil
		package.preload["json"] = function()
			error("disabled")
		end -- luacheck: ignore
		easy_cmds = {}
		awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			easy_cmds[#easy_cmds + 1] = { cmd = cmd, cb = cb }
		end
		awful.spawn.with_line_callback = function(_, _)
			return 0
		end
		pulse = require("continuity.audio.backends.pulse")
		package.preload["json"] = nil
		package.loaded["json"] = saved_json
	end)

	it("resolves icon via by_icon_name when icon_name is present", function()
		local added = {}
		pulse():start({
			inputs = {
				add = function(id, state, meta)
					added[#added + 1] = { id = id, state = state, meta = meta }
				end,
				update = function() end,
				remove = function() end,
			},
		})
		easy_cmds[1].cb(INPUT_WITH_ICON_NAME, "", "", 0)
		assert.equals(1, #app_icon_mock.by_icon_name_calls)
		assert.equals("google-chrome", app_icon_mock.by_icon_name_calls[1].name)
		assert.equals(0, #app_icon_mock.by_app_name_calls)
		assert.equals(0, #added)
		app_icon_mock.by_icon_name_calls[1].cb("/usr/share/pixmaps/google-chrome.png")
		assert.equals(1, #added)
		assert.equals("/usr/share/pixmaps/google-chrome.png", added[1].meta.app_icon)
	end)

	it("resolves icon via by_app_name when only app_name is present", function()
		local added = {}
		pulse():start({
			inputs = {
				add = function(id, state, meta)
					added[#added + 1] = { id = id, state = state, meta = meta }
				end,
				update = function() end,
				remove = function() end,
			},
		})
		easy_cmds[1].cb(INPUT_WITH_APP_NAME_ONLY, "", "", 0)
		assert.equals(0, #app_icon_mock.by_icon_name_calls)
		assert.equals(1, #app_icon_mock.by_app_name_calls)
		assert.equals("spotify", app_icon_mock.by_app_name_calls[1].name)
		assert.equals(0, #added)
		app_icon_mock.by_app_name_calls[1].cb("/usr/share/pixmaps/spotify.png")
		assert.equals(1, #added)
		assert.equals("/usr/share/pixmaps/spotify.png", added[1].meta.app_icon)
	end)

	it("calls add immediately without icon resolution when neither icon_name nor app_name is present", function()
		local added = {}
		pulse():start({
			inputs = {
				add = function(id, state, meta)
					added[#added + 1] = { id = id, state = state, meta = meta }
				end,
				update = function() end,
				remove = function() end,
			},
		})
		easy_cmds[1].cb(INPUT_NO_META, "", "", 0)
		assert.equals(0, #app_icon_mock.by_icon_name_calls)
		assert.equals(0, #app_icon_mock.by_app_name_calls)
		assert.equals(1, #added)
		assert.equals("102", added[1].id)
		assert.is_nil(added[1].meta.app_icon)
	end)
end)
