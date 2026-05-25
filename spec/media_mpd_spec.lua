require("spec.support.awesome_mocks")

local mpd_backend = require("continuity.media.backends.mpd")

describe("mpd._parse_response", function()
	it("parses play state and full track metadata", function()
		local raw = table.concat({
			"state: play",
			"file: Music/Artist/Album/01 Track.flac",
			"Artist: Test Artist",
			"Title: Test Title",
			"Album: Test Album",
			"Genre: Jazz",
			"Date: 2020",
			"Track: 1",
			"Time: 240",
			"elapsed: 12.345",
			"song: 3",
			"playlistlength: 10",
			"volume: 75",
			"repeat: 0",
			"random: 1",
			"single: 0",
			"consume: 1",
		}, "\n")
		local state = mpd_backend._parse_response(raw)
		assert.equals("playing", state.status)
		assert.equals("Test Artist", state.artist)
		assert.equals("Test Title", state.title)
		assert.equals("Test Album", state.album)
		assert.equals("Jazz", state.genre)
		assert.equals("2020", state.date)
		assert.equals(1, state.track_number)
		assert.equals(240, state.duration)
		assert.is_near(12.345, state.position, 0.001)
		assert.equals(3, state.queue_position)
		assert.equals(10, state.queue_length)
		assert.equals(75, state.volume)
		assert.is_true(state.shuffle)
		assert.is_true(state.consume)
	end)

	it("parses Track field in 'n/total' format — takes leading integer", function()
		local state = mpd_backend._parse_response("Track: 5/12")
		assert.equals(5, state.track_number)
	end)

	it("maps repeat=0,single=0 to loop='none'", function()
		assert.equals("none", mpd_backend._parse_response("repeat: 0\nsingle: 0").loop)
	end)

	it("maps repeat=1,single=0 to loop='playlist'", function()
		assert.equals("playlist", mpd_backend._parse_response("repeat: 1\nsingle: 0").loop)
	end)

	it("maps repeat=0,single=1 to loop='track'", function()
		assert.equals("track", mpd_backend._parse_response("repeat: 0\nsingle: 1").loop)
	end)

	it("maps repeat=1,single=1 to loop='track'", function()
		assert.equals("track", mpd_backend._parse_response("repeat: 1\nsingle: 1").loop)
	end)

	it("does NOT set loop when neither repeat nor single appear", function()
		-- A metadata-only partial response must not clobber an existing loop value
		local state = mpd_backend._parse_response("Title: Song\nArtist: Artist")
		assert.is_nil(state.loop)
	end)

	it("maps state=pause to status='paused'", function()
		assert.equals("paused", mpd_backend._parse_response("state: pause").status)
	end)

	it("maps state=stop to status='stopped'", function()
		assert.equals("stopped", mpd_backend._parse_response("state: stop").status)
	end)

	it("populates uri from file field", function()
		assert.equals("spotify:track:abc123", mpd_backend._parse_response("file: spotify:track:abc123").uri)
	end)

	it("leaves art_uri nil (resolved asynchronously by connection loop)", function()
		local state = mpd_backend._parse_response("file: Music/Artist/01.flac")
		assert.is_nil(state.art_uri)
	end)
end)

describe("backend instance", function()
	it("has name equal to label option", function()
		local b = require("continuity.media.backends.mpd")({ label = "my-mpd" })
		assert.equals("my-mpd", b.name)
	end)

	it("does not expose id on the backend table", function()
		local b = require("continuity.media.backends.mpd")({ host = "127.0.0.1", port = 6600 })
		assert.is_nil(b.id)
	end)

	it("does not expose subscribe_position on the backend table", function()
		local b = require("continuity.media.backends.mpd")({})
		assert.is_nil(b.subscribe_position)
	end)

	it("does not expose get_position on the backend table", function()
		local b = require("continuity.media.backends.mpd")({})
		assert.is_nil(b.get_position)
	end)

	it("passes position and playback caps to registry.add()", function()
		package.loaded["continuity.media.backends.mpd"] = nil
		local awful = require("awful")
		awful.spawn.easy_async = function() end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpd")({ host = "127.0.0.1", port = 6600 })
		local caps_received
		local reg = {
			add = function(_, _, _, caps)
				caps_received = caps
			end,
			update = function() end,
			remove = function() end,
		}
		b:start(reg)
		assert.is_not_nil(caps_received)
		assert.is_function(caps_received.position.subscribe)
		assert.is_function(caps_received.position.get)
		assert.is_table(caps_received.playback)
		assert.is_function(caps_received.playback.play)
	end)

	describe("subscribe_position cap", function()
		local caps, gears_mod, spawned_cmds

		before_each(function()
			package.loaded["continuity.media.backends.mpd"] = nil
			gears_mod = require("gears")
			gears_mod._created = {}
			local awful = require("awful")
			spawned_cmds = {}
			awful.spawn.easy_async = function(cmd, cb)
				spawned_cmds[#spawned_cmds + 1] = { cmd = cmd, cb = cb }
			end
			awful.spawn.with_line_callback = function()
				return {}
			end
			local b = require("continuity.media.backends.mpd")({ host = "127.0.0.1", port = 6600 })
			local reg = {
				add = function(_, _, _, c)
					caps = c
				end,
				update = function() end,
				remove = function() end,
			}
			b:start(reg)
		end)

		it("returns a stop function", function()
			local stop = caps.position:subscribe(function() end)
			assert.is_function(stop)
		end)

		it("starts a 1Hz timer", function()
			caps.position:subscribe(function() end)
			assert.equals(1, #gears_mod._created)
		end)

		it("stop_fn stops the timer", function()
			local stop = caps.position:subscribe(function() end)
			local t = gears_mod._created[1]
			stop()
			assert.is_true(t.stopped)
		end)

		it("timer tick calls easy_async", function()
			caps.position:subscribe(function() end)
			gears_mod._created[1]:fire()
			assert.equals(1, #spawned_cmds)
		end)

		it("delivers position via cb when elapsed present", function()
			local received_pos
			caps.position:subscribe(function(p)
				received_pos = p
			end)
			gears_mod._created[1]:fire()
			spawned_cmds[1].cb("state: play\nelapsed: 45.678\nOK\n", "", "", 0)
			assert.is_near(45.678, received_pos, 0.001)
		end)
	end)

	describe("get_position cap", function()
		local caps, spawned_cmds

		before_each(function()
			package.loaded["continuity.media.backends.mpd"] = nil
			local awful = require("awful")
			spawned_cmds = {}
			awful.spawn.easy_async = function(cmd, cb)
				spawned_cmds[#spawned_cmds + 1] = { cmd = cmd, cb = cb }
			end
			awful.spawn.with_line_callback = function()
				return {}
			end
			local b = require("continuity.media.backends.mpd")({ host = "127.0.0.1", port = 6600 })
			local reg = {
				add = function(_, _, _, c)
					caps = c
				end,
				update = function() end,
				remove = function() end,
			}
			b:start(reg)
		end)

		it("makes exactly one easy_async call", function()
			caps.position:get(function() end)
			assert.equals(1, #spawned_cmds)
		end)

		it("delivers elapsed from status response", function()
			local result
			caps.position:get(function(p)
				result = p
			end)
			spawned_cmds[1].cb("elapsed: 12.5\nOK\n", "", "", 0)
			assert.is_near(12.5, result, 0.001)
		end)

		it("delivers nil on failed response", function()
			local result = "not_called"
			caps.position:get(function(p)
				result = p
			end)
			spawned_cmds[1].cb("", "", "", 1)
			assert.is_nil(result)
		end)
	end)
end)

describe("playback commands", function()
	local caps, spawned_cmds, update_calls

	before_each(function()
		package.loaded["continuity.media.backends.mpd"] = nil
		local awful = require("awful")
		spawned_cmds = {}
		awful.spawn.easy_async = function(cmd, cb)
			spawned_cmds[#spawned_cmds + 1] = { cmd = cmd, cb = cb }
			if cb then
				cb("elapsed: 10.000\nOK\n", "", "", 0)
			end
		end
		awful.spawn.with_line_callback = function()
			return {}
		end
		local b = require("continuity.media.backends.mpd")({ host = "127.0.0.1", port = 6600 })
		update_calls = {}
		local reg = {
			add = function(_, _, _, c)
				caps = c
			end,
			update = function(sid, partial)
				update_calls[#update_calls + 1] = { sid = sid, state = partial }
			end,
			remove = function() end,
		}
		b:start(reg)
	end)

	local function make_handle()
		return caps.playback
	end

	it("caps has playback table with all methods", function()
		assert.is_table(caps.playback)
		assert.is_function(caps.playback.play)
		assert.is_function(caps.playback.set_position)
	end)

	local function cmd_payload(idx)
		-- spawned_cmds[idx].cmd is {"sh", "-c", "printf ... | nc ..."}
		-- extract the printf payload from the shell command string
		local shell_cmd = spawned_cmds[idx].cmd[3]
		return shell_cmd
	end

	it("play() sends 'play' command", function()
		local handle = make_handle()
		handle:play()
		assert.is_not_nil(cmd_payload(1):find("play\\\n", 1, true))
	end)

	it("pause() sends 'pause 1' command", function()
		local handle = make_handle()
		handle:pause()
		assert.is_not_nil(cmd_payload(1):find("pause 1\\\n", 1, true))
	end)

	it("play_pause() sends 'pause' with no argument (toggle)", function()
		local handle = make_handle()
		handle:play_pause()
		local payload = cmd_payload(1)
		-- Must contain "pause\<newline>" but NOT "pause 1"
		assert.is_not_nil(payload:find("pause\\\n", 1, true))
		assert.is_nil(payload:find("pause 1", 1, true))
	end)

	it("stop() sends 'stop' command", function()
		local handle = make_handle()
		handle:stop()
		assert.is_not_nil(cmd_payload(1):find("stop\\\n", 1, true))
	end)

	it("next() sends 'next' command", function()
		local handle = make_handle()
		handle:next()
		assert.is_not_nil(cmd_payload(1):find("next\\\n", 1, true))
	end)

	it("previous() sends 'previous' command", function()
		local handle = make_handle()
		handle:previous()
		assert.is_not_nil(cmd_payload(1):find("previous\\\n", 1, true))
	end)

	it("seek(5) sends 'seekcur +5.000'", function()
		local handle = make_handle()
		handle:seek(5)
		assert.is_not_nil(cmd_payload(1):find("seekcur +5.000", 1, true))
	end)

	it("seek(-3) sends 'seekcur -3.000'", function()
		local handle = make_handle()
		handle:seek(-3)
		assert.is_not_nil(cmd_payload(1):find("seekcur -3.000", 1, true))
	end)

	it("seek() pushes position via registry.update in easy_async callback", function()
		-- mock calls cb immediately with "elapsed: 10.000" -> get_position parses 10.0
		-- seekcur cb -> get_position -> parses 10.0 -> registry.update(source_id, {position=10.0})
		local handle = make_handle()
		update_calls = {}
		handle:seek(5)
		assert.equals(1, #update_calls)
		assert.is_near(10.0, update_calls[1].state.position, 0.001)
	end)

	it("set_position(60) sends 'seekcur 60.000' (no sign = absolute)", function()
		local handle = make_handle()
		handle:set_position(60)
		assert.is_not_nil(cmd_payload(1):find("seekcur 60.000", 1, true))
		-- Must NOT have a sign prefix
		assert.is_nil(cmd_payload(1):find("seekcur +60", 1, true))
		assert.is_nil(cmd_payload(1):find("seekcur -60", 1, true))
	end)

	it("set_position() pushes position via registry.update in easy_async callback", function()
		local handle = make_handle()
		update_calls = {}
		handle:set_position(60)
		assert.equals(1, #update_calls)
		assert.is_near(60.0, update_calls[1].state.position, 0.001)
	end)

	it("commands include nc with correct host and port", function()
		local handle = make_handle()
		handle:play()
		assert.is_not_nil(cmd_payload(1):find("nc.*127%.0%.0%.1.*6600", 1, false))
	end)
end)

describe("volume capability", function()
	local caps, update_calls, stdout_cb, spawned_cmds

	before_each(function()
		package.loaded["continuity.media.backends.mpd"] = nil
		local awful = require("awful")
		spawned_cmds = {}
		update_calls = {}
		awful.spawn.with_line_callback = function(_cmd, callbacks)
			stdout_cb = callbacks.stdout
			return {}
		end
		awful.spawn.easy_async = function(cmd, cb)
			spawned_cmds[#spawned_cmds + 1] = { cmd = cmd, cb = cb }
		end
		local b = require("continuity.media.backends.mpd")({ host = "127.0.0.1", port = 6600 })
		local reg = {
			add = function(_, _, _, c)
				caps = c
			end,
			update = function(sid, partial, flags)
				update_calls[#update_calls + 1] = { sid = sid, state = partial, flags = flags }
			end,
			remove = function() end,
		}
		b:start(reg)
	end)

	local function trigger_fetch(response)
		stdout_cb("OK MPD 0.23.5")
		spawned_cmds[#spawned_cmds].cb(response, "", "", 0)
	end

	local function cmd_payload(idx)
		return spawned_cmds[idx].cmd[3]
	end

	it("caps has volume table with set_perc function", function()
		assert.is_table(caps.volume)
		assert.is_function(caps.volume.set_perc)
	end)

	it("initial flags.can_set_volume is true (optimistic; disabled by fetch if volume=-1)", function()
		assert.is_true(caps.flags.can_set_volume)
	end)

	it("fetch_state with volume=75 passes can_set_volume=true in update flags", function()
		trigger_fetch("state: play\nvolume: 75\nOK\n")
		local last = update_calls[#update_calls]
		assert.is_not_nil(last)
		assert.is_not_nil(last.flags)
		assert.is_true(last.flags.can_set_volume)
	end)

	it("fetch_state with volume=75 leaves state.volume as 75", function()
		trigger_fetch("state: play\nvolume: 75\nOK\n")
		local last = update_calls[#update_calls]
		assert.equals(75, last.state.volume)
	end)

	it("fetch_state with volume=-1 passes can_set_volume=false in update flags", function()
		trigger_fetch("state: play\nvolume: -1\nOK\n")
		local last = update_calls[#update_calls]
		assert.is_not_nil(last)
		assert.is_not_nil(last.flags)
		assert.is_false(last.flags.can_set_volume)
	end)

	it("fetch_state with volume=-1 normalizes state.volume to nil", function()
		trigger_fetch("state: play\nvolume: -1\nOK\n")
		local last = update_calls[#update_calls]
		assert.is_nil(last.state.volume)
	end)

	it("set_perc sends setvol command", function()
		caps.volume.set_perc(nil, 75)
		assert.equals(1, #spawned_cmds)
		assert.is_not_nil(cmd_payload(1):find("setvol 75\\\n", 1, true))
	end)

	it("set_perc does not call registry.update", function()
		caps.volume.set_perc(nil, 75)
		assert.equals(0, #update_calls)
	end)

end)
