require("spec.support.awesome_mocks")

describe("audio.backends.alsa", function()
	local alsa

	before_each(function()
		package.loaded["continuity.audio.backends.alsa"] = nil
		alsa = require("continuity.audio.backends.alsa")
	end)

	describe("_parse_channel", function()
		local SGET_OUTPUT = table.concat({
			"Simple mixer control 'Master',0",
			"  Capabilities: pvolume pvolume-joined pswitch pswitch-joined",
			"  Playback channels: Mono",
			"  Limits: Playback 0 - 65536",
			"  Mono: Playback 32768 [50%] [-18.06dB] [on]",
		}, "\n") .. "\n"

		local SGET_MUTED_OUTPUT = table.concat({
			"Simple mixer control 'Master',0",
			"  Capabilities: pvolume pvolume-joined pswitch pswitch-joined",
			"  Playback channels: Mono",
			"  Limits: Playback 0 - 65536",
			"  Mono: Playback 0 [0%] [-inf] [off]",
		}, "\n") .. "\n"

		local CAPTURE_OUTPUT = table.concat({
			"Simple mixer control 'Capture',0",
			"  Capabilities: cvolume cswitch",
			"  Capture channels: Front Left - Front Right",
			"  Front Left: Capture 23799 [72%] [on]",
			"  Front Right: Capture 23799 [72%] [on]",
		}, "\n") .. "\n"

		it("parses level and muted=false when [on]", function()
			local level, muted = alsa._private.parse_channel(SGET_OUTPUT)
			assert.equals(50, level)
			assert.is_false(muted)
		end)

		it("parses level and muted=true when [off]", function()
			local level, muted = alsa._private.parse_channel(SGET_MUTED_OUTPUT)
			assert.equals(0, level)
			assert.is_true(muted)
		end)

		it("parses capture channel output", function()
			local level, muted = alsa._private.parse_channel(CAPTURE_OUTPUT)
			assert.equals(72, level)
			assert.is_false(muted)
		end)

		it("returns nil, nil when output has no percent", function()
			local level, muted =
				alsa._private.parse_channel("amixer: Mixer attach default error: No such file or directory\n")
			assert.is_nil(level)
			assert.is_nil(muted)
		end)

		it("returns nil, nil for empty input", function()
			local level, muted = alsa._private.parse_channel("")
			assert.is_nil(level)
			assert.is_nil(muted)
		end)
	end)
end)

describe("audio.backends.alsa (instance)", function()
	local alsa, awful, wlc_cbs, easy_cmds

	local SGET_MASTER_OUTPUT = table.concat({
		"Simple mixer control 'Master',0",
		"  Mono: Playback 32768 [50%] [-18.06dB] [on]",
	}, "\n") .. "\n"

	local SGET_CAPTURE_OUTPUT = table.concat({
		"Simple mixer control 'Capture',0",
		"  Front Left: Capture 23799 [72%] [on]",
		"  Front Right: Capture 23799 [72%] [on]",
	}, "\n") .. "\n"

	before_each(function()
		package.loaded["continuity.audio.backends.alsa"] = nil
		easy_cmds = {}
		wlc_cbs = nil
		awful = require("awful")
		awful.spawn.easy_async = function(cmd, cb)
			easy_cmds[#easy_cmds + 1] = { cmd = cmd, cb = cb }
		end
		awful.spawn.with_line_callback = function(_cmd, cbs) -- luacheck: ignore _cmd
			wlc_cbs = cbs
			return 0
		end
		alsa = require("continuity.audio.backends.alsa")
	end)

	describe("start", function()
		it("does not poll on start — discovery is event-driven", function()
			alsa():start({ on_sink = function() end, on_source = function() end })
			assert.equals(0, #easy_cmds)
		end)

		it("starts the sevents process", function()
			alsa():start({ on_sink = function() end })
			assert.not_nil(wlc_cbs)
			assert.is_function(wlc_cbs.stdout)
		end)

		it("accepts empty callbacks table", function()
			assert.has_no.errors(function()
				alsa():start({})
			end)
		end)
	end)

	describe("stop", function()
		it("clears callbacks so events after stop do not trigger polls", function()
			local backend = alsa()
			backend:start({ on_sink = function() end })
			backend:stop()
			wlc_cbs.stdout("event value: 'Master',0")
			assert.equals(0, #easy_cmds)
		end)

		it("resets pending counters so they do not suppress events after restart", function()
			local backend = alsa()
			backend:start({ on_sink = function() end })
			backend:adjust_perc("Master", 10, function() end)
			backend:stop()
			backend:start({ on_sink = function() end })
			-- pending was reset; first event should poll
			local count = #easy_cmds
			wlc_cbs.stdout("event value: 'Master',0")
			assert.equals(count + 1, #easy_cmds)
		end)
	end)

	describe("event dispatch", function()
		it("polls sink on Master value event when pending is zero", function()
			local backend = alsa()
			backend:start({ on_sink = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("event value: 'Master',0")
			assert.equals(count + 1, #easy_cmds)
			local cmd = easy_cmds[#easy_cmds].cmd
			assert.same({ "amixer", "sget", "Master" }, cmd)
		end)

		it("polls source on Capture value event when pending is zero", function()
			local backend = alsa()
			backend:start({ on_source = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("event value: 'Capture',0")
			assert.equals(count + 1, #easy_cmds)
			local cmd = easy_cmds[#easy_cmds].cmd
			assert.same({ "amixer", "sget", "Capture" }, cmd)
		end)

		it("ignores non-value lines such as 'Ready to listen...'", function()
			local backend = alsa()
			backend:start({ on_sink = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("Ready to listen...")
			wlc_cbs.stdout("Poll ok")
			assert.equals(count, #easy_cmds)
		end)

		it("ignores value events for unknown channels", function()
			local backend = alsa()
			backend:start({ on_sink = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("event value: 'PCM',0")
			assert.equals(count, #easy_cmds)
		end)

		it("does not poll sink on Master event when on_sink is nil", function()
			local backend = alsa()
			backend:start({ on_source = function() end })
			local count = #easy_cmds
			wlc_cbs.stdout("event value: 'Master',0")
			assert.equals(count, #easy_cmds)
		end)

		it("delivers parsed state to on_sink callback from poll", function()
			local results = {}
			local backend = alsa()
			backend:start({
				on_sink = function(id, s)
					results[#results + 1] = { id = id, state = s }
				end,
			})
			wlc_cbs.stdout("event value: 'Master',0")
			easy_cmds[1].cb(SGET_MASTER_OUTPUT, "", "", 0)
			assert.equals(1, #results)
			assert.equals("Master", results[1].id)
			assert.equals(50, results[1].state.level)
			assert.is_false(results[1].state.muted)
		end)

		it("delivers parsed state to on_source callback from poll", function()
			local results = {}
			local backend = alsa()
			backend:start({
				on_source = function(id, s)
					results[#results + 1] = { id = id, state = s }
				end,
			})
			wlc_cbs.stdout("event value: 'Capture',0")
			easy_cmds[1].cb(SGET_CAPTURE_OUTPUT, "", "", 0)
			assert.equals(1, #results)
			assert.equals("Capture", results[1].id)
			assert.equals(72, results[1].state.level)
		end)

		it("does not deliver to on_sink when poll exits non-zero", function()
			local called = false
			local backend = alsa()
			backend:start({
				on_sink = function()
					called = true
				end,
			})
			wlc_cbs.stdout("event value: 'Master',0")
			easy_cmds[1].cb("", "", "", 1)
			assert.is_false(called)
		end)
	end)

	describe("control API", function()
		local function fire(n, stdout, exitcode)
			easy_cmds[n].cb(stdout or "", "", "", exitcode or 0)
		end

		describe("adjust_perc", function()
			it("positive delta sends %+ command with 'on' to unmute", function()
				local backend = alsa()
				backend:start({})
				backend:adjust_perc("Master", 10, function() end)
				assert.equals(1, #easy_cmds)
				assert.same({ "amixer", "set", "Master", "10%+", "on" }, easy_cmds[1].cmd)
			end)

			it("negative delta sends %- command without mute argument", function()
				local backend = alsa()
				backend:start({})
				backend:adjust_perc("Master", -10, function() end)
				assert.equals(1, #easy_cmds)
				assert.same({ "amixer", "set", "Master", "10%-" }, easy_cmds[1].cmd)
			end)

			it("zero delta sends %+ command with 'on'", function()
				local backend = alsa()
				backend:start({})
				backend:adjust_perc("Master", 0, function() end)
				assert.same({ "amixer", "set", "Master", "0%+", "on" }, easy_cmds[1].cmd)
			end)

			it("calls cb with parsed level and muted from command stdout", function()
				local backend = alsa()
				backend:start({})
				local result = nil
				backend:adjust_perc("Master", 10, function(level, muted)
					result = { level = level, muted = muted }
				end)
				fire(1, SGET_MASTER_OUTPUT)
				assert.not_nil(result)
				assert.equals(50, result.level)
				assert.is_false(result.muted)
			end)

			it("does not call cb when command exits non-zero", function()
				local backend = alsa()
				backend:start({})
				local called = false
				backend:adjust_perc("Master", 10, function()
					called = true
				end)
				fire(1, "", 1)
				assert.is_false(called)
			end)
		end)

		describe("set_perc", function()
			it("sends absolute percent command", function()
				local backend = alsa()
				backend:start({})
				backend:set_perc("Master", 75, function() end)
				assert.equals(1, #easy_cmds)
				assert.same({ "amixer", "set", "Master", "75%" }, easy_cmds[1].cmd)
			end)

			it("floors fractional values", function()
				local backend = alsa()
				backend:start({})
				backend:set_perc("Master", 75.9, function() end)
				assert.same({ "amixer", "set", "Master", "75%" }, easy_cmds[1].cmd)
			end)

			it("calls cb with parsed state from command stdout", function()
				local backend = alsa()
				backend:start({})
				local result = nil
				backend:set_perc("Master", 50, function(level, muted)
					result = { level = level, muted = muted }
				end)
				fire(1, SGET_MASTER_OUTPUT)
				assert.not_nil(result)
				assert.equals(50, result.level)
			end)
		end)

		describe("toggle", function()
			it("sends toggle command", function()
				local backend = alsa()
				backend:start({})
				backend:toggle("Master", function() end)
				assert.equals(1, #easy_cmds)
				assert.same({ "amixer", "set", "Master", "toggle" }, easy_cmds[1].cmd)
			end)

			it("calls cb with parsed state from command stdout", function()
				local backend = alsa()
				backend:start({})
				local result = nil
				backend:toggle("Master", function(level, muted)
					result = { level = level, muted = muted }
				end)
				fire(1, SGET_MASTER_OUTPUT)
				assert.not_nil(result)
				assert.equals(50, result.level)
				assert.is_false(result.muted)
			end)
		end)

		describe("mute", function()
			it("sends 'off' command for Master", function()
				local backend = alsa()
				backend:start({})
				backend:mute("Master", function() end)
				assert.same({ "amixer", "set", "Master", "off" }, easy_cmds[1].cmd)
			end)

			it("sends 'off' command for Capture", function()
				local backend = alsa()
				backend:start({})
				backend:mute("Capture", function() end)
				assert.same({ "amixer", "set", "Capture", "off" }, easy_cmds[1].cmd)
			end)
		end)

		describe("unmute", function()
			it("sends 'on' command for Master", function()
				local backend = alsa()
				backend:start({})
				backend:unmute("Master", function() end)
				assert.same({ "amixer", "set", "Master", "on" }, easy_cmds[1].cmd)
			end)
		end)

		describe("pending counter", function()
			it("Master event is suppressed while pending > 0 for Master", function()
				local backend = alsa()
				backend:start({ on_sink = function() end })
				backend:adjust_perc("Master", 10, function() end)
				local count = #easy_cmds
				-- pending["Master"] == 1: event should decrement, not poll
				wlc_cbs.stdout("event value: 'Master',0")
				assert.equals(count, #easy_cmds)
				-- pending["Master"] == 0: event should poll
				wlc_cbs.stdout("event value: 'Master',0")
				assert.equals(count + 1, #easy_cmds)
			end)

			it("Capture event is not suppressed by Master pending", function()
				local backend = alsa()
				backend:start({ on_sink = function() end, on_source = function() end })
				backend:adjust_perc("Master", 10, function() end)
				local count = #easy_cmds
				-- pending["Capture"] == 0: Capture event should poll
				wlc_cbs.stdout("event value: 'Capture',0")
				assert.equals(count + 1, #easy_cmds)
				-- pending["Master"] == 1: Master event should NOT poll
				wlc_cbs.stdout("event value: 'Master',0")
				assert.equals(count + 1, #easy_cmds)
			end)

			it("pending is decremented on command error so future events are not suppressed", function()
				local backend = alsa()
				backend:start({ on_sink = function() end })
				backend:adjust_perc("Master", 10, function() end)
				-- Simulate command failure
				fire(1, "", 1)
				local count = #easy_cmds
				-- pending should be back to 0; next event polls
				wlc_cbs.stdout("event value: 'Master',0")
				assert.equals(count + 1, #easy_cmds)
			end)
		end)
	end)
end)
