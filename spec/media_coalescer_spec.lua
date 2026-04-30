require("spec.support.awesome_mocks")

local coalescer_mod = require("continuity.media.coalescer")

local function make_inner()
	local spy = { added = {}, updated = {}, removed = {} }
	spy.add = function(id, name, s, caps)
		spy.added[#spy.added + 1] = { id = id, name = name, state = s, caps = caps }
	end
	spy.update = function(id, s, flags)
		spy.updated[#spy.updated + 1] = { id = id, state = s, flags = flags }
	end
	spy.remove = function(id)
		spy.removed[#spy.removed + 1] = id
	end
	return spy
end

local function make_pos_caps(spy)
	spy = spy or {}
	spy.subscribe_calls = 0
	spy.stop_called = false
	spy.position_cb = nil
	spy.get_val = nil
	local caps = {
		position = {
			subscribe = function(source_id, cb)
				spy.subscribe_calls = spy.subscribe_calls + 1
				spy.position_cb = cb
				return function()
					spy.stop_called = true
				end
			end,
			get = function(source_id, cb)
				cb(spy.get_val)
			end,
		},
	}
	return caps, spy
end

local function make_playback_caps()
	local calls = {}
	local exec = {
		play = function(id)
			calls[#calls + 1] = { action = "play", id = id }
		end,
		pause = function(id)
			calls[#calls + 1] = { action = "pause", id = id }
		end,
		play_pause = function(id)
			calls[#calls + 1] = { action = "play_pause", id = id }
		end,
		stop = function(id)
			calls[#calls + 1] = { action = "stop", id = id }
		end,
		next = function(id)
			calls[#calls + 1] = { action = "next", id = id }
		end,
		previous = function(id)
			calls[#calls + 1] = { action = "previous", id = id }
		end,
		seek = function(id, s)
			calls[#calls + 1] = { action = "seek", id = id }
		end,
		set_position = function(id, s)
			calls[#calls + 1] = { action = "set_position", id = id }
		end,
	}
	local flags = {
		can_control = true,
		can_seek = true,
		can_go_next = true,
		can_go_previous = true,
		can_play = true,
		can_pause = true,
	}
	return { playback = exec, flags = flags }, calls
end

local configs = {
	{ id = "spotify", name = "Spotify", backends = { "mpris:spotify", "mpd:127.0.0.1:6600" } },
}

describe("coalescer id routing", function()
	local inner, reg

	before_each(function()
		inner = make_inner()
		reg = coalescer_mod.new(configs).make_registrar(inner)
	end)

	it("make_registrar returns a SourceRegistrar with add/update/remove", function()
		assert.is_function(reg.add)
		assert.is_function(reg.update)
		assert.is_function(reg.remove)
	end)

	it("unified source added on first backend add with configured display name", function()
		reg.add("mpris:spotify", "spotify", { title = "T" })
		assert.equals(1, #inner.added)
		assert.equals("spotify", inner.added[1].id)
		assert.equals("Spotify", inner.added[1].name)
	end)

	it("display name falls back to backend name when config name absent", function()
		local no_name_configs = { { id = "vlc", backends = { "mpris:vlc" } } }
		local spy = make_inner()
		local r2 = coalescer_mod.new(no_name_configs).make_registrar(spy)
		r2.add("mpris:vlc", "VLC Player", {})
		assert.equals("VLC Player", spy.added[1].name)
	end)

	it("second backend add merges initial state via inner.update, not inner.add", function()
		reg.add("mpris:spotify", "spotify", { title = "T" })
		reg.add("mpd:127.0.0.1:6600", "mpd", { status = "playing" })
		assert.equals(1, #inner.added)
		assert.equals(1, #inner.updated)
		assert.equals("spotify", inner.updated[1].id)
	end)

	it("re-add by same active backend merges rather than re-adds", function()
		reg.add("mpris:spotify", "spotify", { title = "A" })
		reg.add("mpris:spotify", "spotify", { title = "B" })
		assert.equals(1, #inner.added)
		assert.equals(1, #inner.updated)
	end)

	it("update from either backend forwards to unified source id", function()
		reg.add("mpris:spotify", "spotify", {})
		reg.add("mpd:127.0.0.1:6600", "mpd", {})
		inner.updated = {}
		reg.update("mpris:spotify", { title = "New" })
		assert.equals("spotify", inner.updated[1].id)
		reg.update("mpd:127.0.0.1:6600", { status = "paused" })
		assert.equals("spotify", inner.updated[2].id)
	end)

	it("update before add is a no-op", function()
		reg.update("mpris:spotify", { title = "Ghost" })
		assert.equals(0, #inner.updated)
	end)

	it("remove from one backend does not remove unified source while other is active", function()
		reg.add("mpris:spotify", "spotify", {})
		reg.add("mpd:127.0.0.1:6600", "mpd", {})
		reg.remove("mpris:spotify")
		assert.equals(0, #inner.removed)
	end)

	it("remove from last active backend removes unified source", function()
		reg.add("mpris:spotify", "spotify", {})
		reg.remove("mpris:spotify")
		assert.equals(1, #inner.removed)
		assert.equals("spotify", inner.removed[1])
	end)

	it("re-add after full remove registers unified source via inner.add again", function()
		reg.add("mpris:spotify", "spotify", {})
		reg.remove("mpris:spotify")
		inner.added = {}
		reg.add("mpris:spotify", "spotify", { title = "Fresh" })
		assert.equals(1, #inner.added)
		assert.equals("spotify", inner.added[1].id)
	end)

	it("unconfigured backend passes through for add, update, and remove", function()
		reg.add("mpris:vlc", "vlc", { title = "Track" })
		assert.equals("mpris:vlc", inner.added[1].id)
		reg.update("mpris:vlc", { status = "playing" })
		assert.equals("mpris:vlc", inner.updated[1].id)
		reg.remove("mpris:vlc")
		assert.equals("mpris:vlc", inner.removed[1])
	end)

	it("merged caps passed to inner.add on first backend add", function()
		reg.add("mpris:spotify", "spotify", {})
		local caps = inner.added[1].caps
		assert.is_table(caps)
		assert.is_table(caps.position)
		assert.is_function(caps.position.subscribe)
		assert.is_function(caps.position.get)
		assert.is_table(caps.playback)
	end)
end)

describe("coalescer merged position caps", function()
	local inner

	before_each(function()
		inner = make_inner()
	end)

	local pos_configs = {
		{ id = "spotify", backends = { "mpris:spotify", "mpd:127.0.0.1:6600" } },
	}

	it("position.subscribe routes to highest-priority active backend", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		local caps_mpd, spy_mpd = make_pos_caps()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		inner.added[1].caps.position.subscribe("spotify", function() end)
		assert.equals(1, spy_mpris.subscribe_calls)
		assert.equals(0, spy_mpd.subscribe_calls)
	end)

	it("merged position.subscribe fans out position to provided cb", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		local received
		inner.added[1].caps.position.subscribe("spotify", function(p)
			received = p
		end)
		spy_mpris.position_cb(42.0)
		assert.is_near(42.0, received, 0.001)
	end)

	it("stop_fn from merged subscribe stops the backend subscription", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		local stop = inner.added[1].caps.position.subscribe("spotify", function() end)
		stop()
		assert.is_true(spy_mpris.stop_called)
	end)

	it("higher-priority backend arriving after subscription swaps position owner", function()
		local caps_mpd, spy_mpd = make_pos_caps()
		local caps_mpris, spy_mpris = make_pos_caps()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		inner.added[1].caps.position.subscribe("spotify", function() end)
		assert.equals(1, spy_mpd.subscribe_calls)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		assert.is_true(spy_mpd.stop_called)
		assert.equals(1, spy_mpris.subscribe_calls)
	end)

	it("lower-priority backend arriving after subscription does not take over", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		local caps_mpd, spy_mpd = make_pos_caps()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		inner.added[1].caps.position.subscribe("spotify", function() end)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		assert.is_false(spy_mpris.stop_called)
		assert.equals(0, spy_mpd.subscribe_calls)
	end)

	it("removing position owner re-routes to next best backend", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		local caps_mpd, spy_mpd = make_pos_caps()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		inner.added[1].caps.position.subscribe("spotify", function() end)
		reg.remove("mpris:spotify")
		assert.is_true(spy_mpris.stop_called)
		assert.equals(1, spy_mpd.subscribe_calls)
	end)

	it("removing last backend with active subscription cleans up before inner.remove", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		inner.added[1].caps.position.subscribe("spotify", function() end)
		reg.remove("mpris:spotify")
		-- stop_fn called, inner.remove called
		assert.is_true(spy_mpris.stop_called)
		assert.equals(1, #inner.removed)
		assert.equals("spotify", inner.removed[1])
	end)

	it("removing owner with no capable fallback leaves subscription inactive", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		local caps_mpd_no_pos = {} -- no position cap
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd_no_pos)
		local received = {}
		inner.added[1].caps.position.subscribe("spotify", function(p)
			received[#received + 1] = p
		end)
		reg.remove("mpris:spotify")
		assert.is_true(spy_mpris.stop_called)
		assert.equals(0, #received)
	end)

	it("position.get routes to position_owner when subscription is active", function()
		local caps_mpd, spy_mpd = make_pos_caps()
		local caps_mpris, spy_mpris = make_pos_caps()
		spy_mpd.get_val = 10.0
		spy_mpris.get_val = 20.0
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		inner.added[1].caps.position.subscribe("spotify", function() end)
		-- mpris owns (higher priority)
		local result
		inner.added[1].caps.position.get("spotify", function(p)
			result = p
		end)
		assert.is_near(20.0, result, 0.001)
	end)

	it("position.get falls back to highest-priority capable backend when no owner", function()
		local caps_mpris, spy_mpris = make_pos_caps()
		spy_mpris.get_val = 55.0
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		local result
		inner.added[1].caps.position.get("spotify", function(p)
			result = p
		end)
		assert.is_near(55.0, result, 0.001)
	end)

	it("position.get calls cb(nil) when no capable backend active", function()
		local reg = coalescer_mod.new(pos_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}) -- no caps
		local result = "not_called"
		inner.added[1].caps.position.get("spotify", function(p)
			result = p
		end)
		assert.is_nil(result)
	end)
end)

describe("coalescer merged playback caps", function()
	local inner

	before_each(function()
		inner = make_inner()
	end)

	local play_configs = {
		{ id = "spotify", backends = { "mpris:spotify", "mpd:127.0.0.1:6600" } },
	}

	it("playback routes to highest-priority active backend", function()
		local caps_mpris, calls_mpris = make_playback_caps()
		local caps_mpd, calls_mpd = make_playback_caps()
		local reg = coalescer_mod.new(play_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		inner.added[1].caps.playback.play("spotify")
		assert.equals(1, #calls_mpris)
		assert.equals(0, #calls_mpd)
	end)

	it("playback is a no-op when no backend with playback is active", function()
		local reg = coalescer_mod.new(play_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}) -- no caps
		assert.is_table(inner.added[1].caps.playback)
		inner.added[1].caps.playback.play("spotify") -- should not error
	end)

	it("playback falls back to lower-priority backend when higher is removed", function()
		local caps_mpris, calls_mpris = make_playback_caps()
		local caps_mpd, calls_mpd = make_playback_caps()
		local reg = coalescer_mod.new(play_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		reg.remove("mpris:spotify")
		inner.added[1].caps.playback.play("spotify")
		assert.equals(0, #calls_mpris)
		assert.equals(1, #calls_mpd)
	end)

	it("playback is a no-op after owner removed with no capable fallback", function()
		local caps_mpris, calls_mpris = make_playback_caps()
		local reg = coalescer_mod.new(play_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, caps_mpris)
		reg.add("mpd:127.0.0.1:6600", "mpd", {}) -- no playback cap
		reg.remove("mpris:spotify")
		inner.added[1].caps.playback.play("spotify") -- should not error
		assert.equals(0, #calls_mpris)
	end)
end)

describe("coalescer playback_capabilities forwarding", function()
	local play_configs = {
		{ id = "spotify", backends = { "mpris:spotify", "mpd:127.0.0.1:6600" } },
	}

	local function make_caps_spy_inner()
		local spy = { added = {}, updated = {}, removed = {} }
		spy.add = function(id, name, s, caps)
			spy.added[#spy.added + 1] = { id = id, caps = caps }
		end
		spy.update = function(id, s, flags)
			spy.updated[#spy.updated + 1] = { id = id, state = s, flags = flags }
		end
		spy.remove = function(id)
			spy.removed[#spy.removed + 1] = id
		end
		return spy
	end

	local function make_pb_caps()
		local exec = {
			play = function() end,
			pause = function() end,
			play_pause = function() end,
			stop = function() end,
			next = function() end,
			previous = function() end,
			seek = function() end,
			set_position = function() end,
		}
		local flags = {
			can_control = true,
			can_seek = true,
			can_go_next = true,
			can_go_previous = true,
			can_play = true,
			can_pause = true,
		}
		return { playback = exec, flags = flags }
	end

	it("playback_capabilities forwarded to inner.update when backend is playback owner", function()
		local inner = make_caps_spy_inner()
		local reg = coalescer_mod.new(play_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, make_pb_caps())
		inner.updated = {}
		reg.update("mpris:spotify", {}, { can_go_next = false, can_seek = true })
		assert.equals(1, #inner.updated)
		assert.is_not_nil(inner.updated[1].flags)
		assert.is_false(inner.updated[1].flags.can_go_next)
		assert.is_true(inner.updated[1].flags.can_seek)
	end)

	it("playback_capabilities not forwarded when backend is not playback owner", function()
		local inner = make_caps_spy_inner()
		local reg = coalescer_mod.new(play_configs).make_registrar(inner)
		reg.add("mpris:spotify", "spotify", {}, make_pb_caps())
		reg.add("mpd:127.0.0.1:6600", "mpd", {}, make_pb_caps())
		inner.updated = {}
		reg.update("mpd:127.0.0.1:6600", {}, { can_go_next = false })
		assert.equals(1, #inner.updated)
		assert.is_nil(inner.updated[1].flags)
	end)

	it("unconfigured backend passes playback_capabilities through unchanged", function()
		local inner = make_caps_spy_inner()
		local reg = coalescer_mod.new(play_configs).make_registrar(inner)
		reg.update("mpris:vlc", { title = "T" }, { can_go_next = false })
		assert.equals(1, #inner.updated)
		assert.is_not_nil(inner.updated[1].flags)
		assert.is_false(inner.updated[1].flags.can_go_next)
	end)
end)

describe("coalescer playback flag sync on ownership change", function()
	local flag_sync_configs = {
		{ id = "spotify", backends = { "mpris:spotify", "mpd:127.0.0.1:6600" } },
	}

	it("flags from new playback owner forwarded to inner.update when owner changes", function()
		local inner2 = make_inner()
		local caps_mpris, _ = make_playback_caps()
		local caps_mpd, _ = make_playback_caps()
		caps_mpd.flags.can_go_next = false -- distinguishing flag
		local reg2 = coalescer_mod.new(flag_sync_configs).make_registrar(inner2)
		reg2.add("mpris:spotify", "spotify", {}, caps_mpris)
		-- mpd is lower priority; mpris stays owner; add is NOT the first add for mpd
		reg2.add("mpd:127.0.0.1:6600", "mpd", {}, caps_mpd)
		-- Now remove mpris; mpd becomes owner; flags must sync
		inner2.updated = {}
		reg2.remove("mpris:spotify")
		-- inner2.updated should contain a flag-sync update with mpd's flags
		local flag_update
		for _, u in ipairs(inner2.updated) do
			if u.flags then
				flag_update = u
			end
		end
		assert.is_not_nil(flag_update)
		assert.is_false(flag_update.flags.can_go_next)
	end)

	it("can_control=false update sent when no playback owner remains after remove", function()
		local inner2 = make_inner()
		local caps_mpris, _ = make_playback_caps()
		local reg2 = coalescer_mod.new(flag_sync_configs).make_registrar(inner2)
		reg2.add("mpris:spotify", "spotify", {}, caps_mpris)
		inner2.updated = {}
		reg2.remove("mpris:spotify")
		-- inner.remove fires, but before that: flag sync with can_control=false
		local flag_update
		for _, u in ipairs(inner2.updated) do
			if u.flags then
				flag_update = u
			end
		end
		assert.is_not_nil(flag_update)
		assert.is_false(flag_update.flags.can_control)
	end)
end)
