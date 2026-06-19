require("spec.support.awesome_mocks")

local registry = require("continuity.media.registry")

describe("registry", function()
	local reg
	local registrar

	before_each(function()
		reg, registrar = registry.new()
	end)

	describe("add", function()
		it("fires on_added callback with correct source", function()
			local called_with
			reg:on_added(function(source)
				called_with = source
			end)
			registrar.add("mpd:127.0.0.1:6600", "mpd", { title = "Test Track" })
			assert.is_not_nil(called_with)
			assert.equals("mpd:127.0.0.1:6600", called_with.id)
			assert.equals("mpd", called_with.name)
			assert.equals("Test Track", called_with.state.title)
		end)

		it("makes source visible via all()", function()
			registrar.add("mpd:127.0.0.1:6600", "mpd", { title = "Test" })
			local sources = reg:all()
			assert.equals(1, #sources)
			assert.equals("mpd:127.0.0.1:6600", sources[1].id)
		end)

		it("all() returns a copy — modifying it does not affect registry", function()
			registrar.add("mpd:127.0.0.1:6600", "mpd", {})
			local snap = reg:all()
			snap[1] = nil
			assert.equals(1, #reg:all())
		end)

		it("stores app_icon on source when passed as sixth argument", function()
			registrar.add("mpris:spotify", "spotify", {}, nil, "spotify", "/usr/share/icons/spotify.png")
			local sources = reg:all()
			assert.equals("/usr/share/icons/spotify.png", sources[1].app_icon)
		end)

		it("source has nil app_icon when not provided", function()
			registrar.add("mpris:spotify", "spotify", {})
			local sources = reg:all()
			assert.is_nil(sources[1].app_icon)
		end)
	end)

	describe("update", function()
		before_each(function()
			registrar.add("mpd:127.0.0.1:6600", "mpd", { title = "Original", artist = "Artist" })
		end)

		it("merges partial state and fires on_updated", function()
			local called_with
			reg:on_updated(function(source)
				called_with = source
			end)
			registrar.update("mpd:127.0.0.1:6600", { status = "playing" })
			assert.equals("playing", called_with.state.status)
			assert.equals("Original", called_with.state.title) -- unchanged field preserved
			assert.equals("Artist", called_with.state.artist) -- unchanged field preserved
		end)

		it("treats nil value same as absent — does not clear field", function()
			registrar.update("mpd:127.0.0.1:6600", { title = nil })
			local sources = reg:all()
			assert.equals("Original", sources[1].state.title)
		end)

		it("does not fire callback for unknown source_id", function()
			local called = false
			reg:on_updated(function()
				called = true
			end)
			registrar.update("unknown:id", { title = "X" })
			assert.is_false(called)
		end)

		describe("with playback_capabilities", function()
			local function make_executor()
				return {
					play = function() end,
					pause = function() end,
					play_pause = function() end,
					stop = function() end,
					next = function() end,
					previous = function() end,
					seek = function() end,
					set_position = function() end,
				}
			end
			local function make_flags(overrides)
				local f = {
					can_control = true,
					can_seek = true,
					can_go_next = true,
					can_go_previous = true,
					can_play = true,
					can_pause = true,
				}
				for k, v in pairs(overrides or {}) do
					f[k] = v
				end
				return f
			end

			before_each(function()
				reg, registrar = registry.new()
			end)

			it("capabilities-only update (empty state) fires on_updated", function()
				registrar.add("src:1", "source", {}, { playback = make_executor(), flags = make_flags() })
				local called = false
				reg:on_updated(function()
					called = true
				end)
				registrar.update(
					"src:1",
					{},
					{ can_seek = false, can_go_next = true, can_go_previous = true, can_play = true, can_pause = true }
				)
				assert.is_true(called)
			end)

			it("flags booleans are merged into source.playback", function()
				registrar.add("src:1", "source", {}, { playback = make_executor(), flags = make_flags() })
				registrar.update(
					"src:1",
					{},
					{ can_seek = false, can_go_next = true, can_go_previous = false, can_play = true, can_pause = true }
				)
				local playback = reg:all()[1].playback
				assert.is_false(playback.can_seek)
				assert.is_true(playback.can_go_next)
				assert.is_false(playback.can_go_previous)
			end)

			it("partial flags update preserves absent fields", function()
				registrar.add("src:1", "source", {}, { playback = make_executor(), flags = make_flags() })
				registrar.update("src:1", {}, { can_pause = false })
				local playback = reg:all()[1].playback
				assert.is_false(playback.can_pause)
				assert.is_true(playback.can_seek)
				assert.is_true(playback.can_go_next)
				assert.is_true(playback.can_go_previous)
				assert.is_true(playback.can_play)
			end)

			it("flags update is a no-op when source.playback is nil", function()
				registrar.add("src:1", "source", {})
				assert.has_no.errors(function()
					registrar.update("src:1", {}, {
						can_seek = true,
						can_go_next = true,
						can_go_previous = true,
						can_play = true,
						can_pause = true,
					})
				end)
			end)
		end)
	end)

	describe("remove", function()
		before_each(function()
			registrar.add("mpd:127.0.0.1:6600", "mpd", {})
		end)

		it("fires on_removed with the source_id", function()
			local removed_id
			reg:on_removed(function(id)
				removed_id = id
			end)
			registrar.remove("mpd:127.0.0.1:6600")
			assert.equals("mpd:127.0.0.1:6600", removed_id)
		end)

		it("removes source from all()", function()
			registrar.remove("mpd:127.0.0.1:6600")
			assert.equals(0, #reg:all())
		end)

		it("source_id from remove matches id from add", function()
			local added_id, removed_id
			local reg2, reg2_registrar = registry.new()
			reg2:on_added(function(s)
				added_id = s.id
			end)
			reg2:on_removed(function(id)
				removed_id = id
			end)
			reg2_registrar.add("mpris:spotify", "spotify", {})
			reg2_registrar.remove("mpris:spotify")
			assert.equals(added_id, removed_id)
		end)
	end)

	describe("multiple callbacks", function()
		it("calls all registered on_added callbacks", function()
			local count = 0
			reg:on_added(function()
				count = count + 1
			end)
			reg:on_added(function()
				count = count + 1
			end)
			registrar.add("x", "x", {})
			assert.equals(2, count)
		end)
	end)

	describe("registrar", function()
		it("exposes add/update/remove that route through registry callbacks", function()
			local added
			reg:on_added(function(s)
				added = s
			end)
			registrar.add("mpris:vlc", "vlc", { title = "Track" })
			assert.is_not_nil(added)
			assert.equals("mpris:vlc", added.id)
		end)

		it("does not expose position, set_get_position, or set_playback", function()
			assert.is_nil(registrar.position)
			assert.is_nil(registrar.set_get_position)
			assert.is_nil(registrar.set_playback)
		end)
	end)

	describe("position push", function()
		it("position field in update fires fan-out to position.subscribe cb", function()
			registrar.add("src:1", "source", {})
			local source = reg:all()[1]
			local got_pos
			source.position:subscribe(function(p)
				got_pos = p
			end)
			registrar.update("src:1", { position = 5.5 })
			assert.is_near(5.5, got_pos, 0.001)
		end)
	end)

	describe("source.position", function()
		local function make_position_caps(spy)
			spy = spy or {}
			spy.subscribe_calls = 0
			spy.stop_called = false
			spy.position_cb = nil
			local caps = {
				position = {
					subscribe = function(_source_id, cb)
						spy.subscribe_calls = spy.subscribe_calls + 1
						spy.position_cb = cb
						return function()
							spy.stop_called = true
						end
					end,
					get = function(_source_id, cb)
						cb(spy.get_val)
					end,
				},
			}
			return caps, spy
		end

		it("source.position is a table with subscribe and get", function()
			registrar.add("src:1", "source", {})
			local source = reg:all()[1]
			assert.is_table(source.position)
			assert.is_function(source.position.subscribe)
			assert.is_function(source.position.get)
		end)

		it("position.subscribe returns a stop_fn", function()
			registrar.add("src:1", "source", {})
			local source = reg:all()[1]
			local stop = source.position:subscribe(function() end)
			assert.is_function(stop)
		end)

		it("stop_fn removes subscriber — no more calls after stop", function()
			registrar.add("src:1", "source", {})
			local source = reg:all()[1]
			local calls = 0
			local stop = source.position:subscribe(function()
				calls = calls + 1
			end)
			registrar.update("src:1", { position = 1.0 })
			stop()
			registrar.update("src:1", { position = 2.0 })
			assert.equals(1, calls)
		end)

		it("caps.position.subscribe called when first position.subscribe listener added", function()
			local caps, spy = make_position_caps()
			registrar.add("src:1", "source", {}, caps)
			local source = reg:all()[1]
			assert.equals(0, spy.subscribe_calls)
			source.position:subscribe(function() end)
			assert.equals(1, spy.subscribe_calls)
		end)

		it("caps.position.subscribe not called again for second listener", function()
			local caps, spy = make_position_caps()
			registrar.add("src:1", "source", {}, caps)
			local source = reg:all()[1]
			source.position:subscribe(function() end)
			source.position:subscribe(function() end)
			assert.equals(1, spy.subscribe_calls)
		end)

		it("position callback from caps fans out to position.subscribe listeners", function()
			local caps, spy = make_position_caps()
			registrar.add("src:1", "source", {}, caps)
			local source = reg:all()[1]
			local received
			source.position:subscribe(function(p)
				received = p
			end)
			spy.position_cb(99.5)
			assert.is_near(99.5, received, 0.001)
		end)

		it("stop_fn from caps called when last listener removed", function()
			local caps, spy = make_position_caps()
			registrar.add("src:1", "source", {}, caps)
			local source = reg:all()[1]
			local stop = source.position:subscribe(function() end)
			assert.is_false(spy.stop_called)
			stop()
			assert.is_true(spy.stop_called)
		end)

		it("caps stop_fn not called until last listener removed", function()
			local caps, spy = make_position_caps()
			registrar.add("src:1", "source", {}, caps)
			local source = reg:all()[1]
			local stop1 = source.position:subscribe(function() end)
			local stop2 = source.position:subscribe(function() end)
			stop1()
			assert.is_false(spy.stop_called)
			stop2()
			assert.is_true(spy.stop_called)
		end)

		it("caps stop_fn called when source removed with active listener", function()
			local caps, spy = make_position_caps()
			registrar.add("src:1", "source", {}, caps)
			local source = reg:all()[1]
			source.position:subscribe(function() end)
			registrar.remove("src:1")
			assert.is_true(spy.stop_called)
		end)

		it("position.subscribe cb receives pos only (not source)", function()
			registrar.add("src:1", "source", {})
			local source = reg:all()[1]
			local args = {}
			source.position:subscribe(function(...)
				args = { ... }
			end)
			registrar.update("src:1", { position = 7.0 })
			assert.equals(1, #args)
			assert.is_near(7.0, args[1], 0.001)
		end)

		it("position.get routes to caps.position.get", function()
			local caps, spy = make_position_caps()
			spy.get_val = 42.0
			registrar.add("src:1", "source", {}, caps)
			local source = reg:all()[1]
			local result
			source.position:get(function(p)
				result = p
			end)
			assert.is_near(42.0, result, 0.001)
		end)

		it("position.get calls cb(nil) when no caps provided", function()
			registrar.add("src:1", "source", {})
			local source = reg:all()[1]
			local result = "not_called"
			source.position:get(function(p)
				result = p
			end)
			assert.is_nil(result)
		end)
	end)

	describe("update position extraction", function()
		it("position field in update triggers fan-out", function()
			registrar.add("src:1", "source", {})
			local source = reg:all()[1]
			local received_pos
			source.position:subscribe(function(p)
				received_pos = p
			end)
			registrar.update("src:1", { position = 30.0 })
			assert.is_near(30.0, received_pos, 0.001)
		end)

		it("position update still sets state.position", function()
			registrar.add("src:1", "source", {})
			registrar.update("src:1", { position = 15.0 })
			assert.is_near(15.0, reg:all()[1].state.position, 0.001)
		end)

		it("non-position fields still fire on_updated when position also present", function()
			registrar.add("src:1", "source", { title = "Old" })
			local updated
			reg:on_updated(function(s)
				updated = s
			end)
			registrar.update("src:1", { title = "New", position = 5.0 })
			assert.equals("New", updated.state.title)
		end)

		it("position-only update does not fire on_updated", function()
			registrar.add("src:1", "source", {})
			local called = false
			reg:on_updated(function()
				called = true
			end)
			registrar.update("src:1", { position = 10.0 })
			assert.is_false(called)
		end)
	end)

	describe("playback boundary", function()
		before_each(function()
			reg, registrar = registry.new()
			registrar.add("src:1", "source", { title = "Song A", artist = "Artist" })
		end)

		it("update clears stale state when title changes", function()
			registrar.update("src:1", { title = "Song B" })
			assert.is_nil(reg:all()[1].state.artist)
		end)

		it("update clears stale state when uri changes", function()
			registrar.update("src:1", { uri = "x:1" })
			registrar.update("src:1", { uri = "x:2" })
			assert.is_nil(reg:all()[1].state.artist)
		end)

		it("update clears stale state when track_id changes", function()
			registrar.update("src:1", { track_id = "/Track/1" })
			registrar.update("src:1", { track_id = "/Track/2" })
			assert.is_nil(reg:all()[1].state.artist)
		end)

		it("update clears stale state when artist changes", function()
			registrar.update("src:1", { artist = "New Artist" })
			-- title was set on add; after boundary clear it should be gone
			assert.is_nil(reg:all()[1].state.title)
		end)

		it("does not clear when boundary field is unchanged", function()
			registrar.update("src:1", { title = "Song A" })
			assert.equals("Artist", reg:all()[1].state.artist)
		end)

		it("does not clear for non-boundary field updates", function()
			registrar.update("src:1", { status = "paused" })
			assert.equals("Song A", reg:all()[1].state.title)
			assert.equals("Artist", reg:all()[1].state.artist)
		end)

		it("new boundary field values are present after clear", function()
			registrar.update("src:1", { title = "Song B", album = "Album B" })
			assert.equals("Song B", reg:all()[1].state.title)
			assert.equals("Album B", reg:all()[1].state.album)
		end)

		it("boundary state is seeded from initial add — no spurious clear on first update", function()
			-- title was set on add; updating with same title should not clear
			registrar.update("src:1", { title = "Song A", status = "playing" })
			assert.equals("Artist", reg:all()[1].state.artist)
		end)

		it("preserves status across a track boundary", function()
			registrar.update("src:1", { status = "playing" })
			registrar.update("src:1", { title = "Song B" })
			assert.equals("playing", reg:all()[1].state.status)
		end)

		it("preserves volume, shuffle, and loop across a track boundary", function()
			registrar.update("src:1", { volume = 80, shuffle = true, loop = "track" })
			registrar.update("src:1", { title = "Song B" })
			local s = reg:all()[1].state
			assert.equals(80, s.volume)
			assert.is_true(s.shuffle)
			assert.equals("track", s.loop)
		end)

		it("clears track-specific fields not in boundary set (album, art_uri, duration) on boundary", function()
			registrar.update("src:1", { album = "Album A", art_uri = "file://art.png", duration = 240 })
			registrar.update("src:1", { title = "Song B" })
			local s = reg:all()[1].state
			assert.is_nil(s.album)
			assert.is_nil(s.art_uri)
			assert.is_nil(s.duration)
		end)
	end)

	describe("source.playback", function()
		local function make_executor()
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
					calls[#calls + 1] = { action = "seek", id = id, secs = s }
				end,
				set_position = function(id, s)
					calls[#calls + 1] = { action = "set_position", id = id, secs = s }
				end,
			}
			return exec, calls
		end

		local function make_vol_executor()
			local calls = {}
			local exec = {
				set_perc = function(id, pct)
					calls[#calls + 1] = { action = "set_perc", id = id, pct = pct }
				end,
			}
			return exec, calls
		end

		local function make_flags(overrides)
			local f = {
				can_control = true,
				can_seek = true,
				can_go_next = true,
				can_go_previous = true,
				can_play = true,
				can_pause = true,
				can_set_volume = true,
			}
			for k, v in pairs(overrides or {}) do
				f[k] = v
			end
			return f
		end

		before_each(function()
			reg, registrar = registry.new()
		end)

		it("source.playback is nil when no capabilities", function()
			registrar.add("src:1", "source", {})
			assert.is_nil(reg:all()[1].playback)
		end)

		it("source.playback is nil when capabilities has no playback field", function()
			registrar.add("src:1", "source", {}, { flags = make_flags() })
			assert.is_nil(reg:all()[1].playback)
		end)

		it("source.playback is nil when can_control is false", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags({ can_control = false }) })
			assert.is_nil(reg:all()[1].playback)
		end)

		it("source.playback is a Playback table when executor and flags provided", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags() })
			local pb = reg:all()[1].playback
			assert.is_table(pb)
			assert.is_function(pb.play)
			assert.is_function(pb.previous)
		end)

		it("Playback has can_* flags from initial PlaybackFlags", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, {
				playback = exec,
				flags = make_flags({ can_seek = false, can_go_next = true, can_go_previous = false }),
			})
			local pb = reg:all()[1].playback
			assert.is_false(pb.can_seek)
			assert.is_true(pb.can_go_next)
			assert.is_false(pb.can_go_previous)
		end)

		it("Playback.previous() calls executor.previous with source_id", function()
			local exec, calls = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags() })
			reg:all()[1].playback:previous()
			assert.equals(1, #calls)
			assert.equals("previous", calls[1].action)
			assert.equals("src:1", calls[1].id)
		end)

		it("Playback.next() respects can_go_next guard", function()
			local exec, calls = make_executor()
			registrar.add("src:1", "source", {}, {
				playback = exec,
				flags = make_flags({ can_go_next = false }),
			})
			reg:all()[1].playback:next()
			assert.equals(0, #calls)
		end)

		it("Playback.play() fires on_playback_action with Play", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags() })
			local fired_source, fired_action
			reg.on_playback_action(function(s, a)
				fired_source = s
				fired_action = a
			end)
			reg:all()[1].playback:play()
			assert.equals("src:1", fired_source.id)
			assert.equals(registry.PlaybackAction.Play, fired_action)
		end)

		it("Playback.previous() fires on_playback_action with Previous", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags() })
			local fired_action
			reg.on_playback_action(function(_, a)
				fired_action = a
			end)
			reg:all()[1].playback:previous()
			assert.equals(registry.PlaybackAction.Previous, fired_action)
		end)

		it("on_playback_action does not fire when can_* guard blocks the action", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, {
				playback = exec,
				flags = make_flags({ can_go_next = false }),
			})
			local fired = false
			reg.on_playback_action(function()
				fired = true
			end)
			reg:all()[1].playback:next()
			assert.is_false(fired)
		end)

		it("r.update flags merges can_* into existing Playback in-place", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags({ can_go_next = true }) })
			registrar.update(
				"src:1",
				{},
				{ can_go_next = false, can_seek = false, can_go_previous = true, can_play = true, can_pause = true }
			)
			assert.is_false(reg:all()[1].playback.can_go_next)
		end)

		it("r.update with can_control=false nils source.playback", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags() })
			registrar.update("src:1", {}, { can_control = false })
			assert.is_nil(reg:all()[1].playback)
		end)

		it("registrar.add works with executor-style capabilities", function()
			local exec = make_executor()
			registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags() })
			assert.is_table(reg:all()[1].playback)
		end)

		describe("playback.volume", function()
			it("is nil when no VolumeCapability provided", function()
				local exec = make_executor()
				registrar.add("src:1", "source", {}, { playback = exec, flags = make_flags() })
				assert.is_nil(reg:all()[1].playback.volume)
			end)

			it("is nil when can_set_volume is false", function()
				local exec, vol_exec = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", {}, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags({ can_set_volume = false }),
				})
				assert.is_nil(reg:all()[1].playback.volume)
			end)

			it("is a table when VolumeCapability present and can_set_volume true", function()
				local exec, vol_exec = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", {}, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				assert.is_table(reg:all()[1].playback.volume)
				assert.is_function(reg:all()[1].playback.volume.set_perc)
				assert.is_function(reg:all()[1].playback.volume.adjust_perc)
			end)

			it("set_perc calls vol_executor.set_perc with source_id and value", function()
				local exec, vol_exec, vol_calls = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", {}, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				reg:all()[1].playback.volume:set_perc(60)
				assert.equals(1, #vol_calls)
				assert.equals("set_perc", vol_calls[1].action)
				assert.equals("src:1", vol_calls[1].id)
				assert.equals(60, vol_calls[1].pct)
			end)

			it("set_perc fires on_playback_action with SetVolume", function()
				local exec, vol_exec = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", {}, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				local actions = {}
				reg.on_playback_action(function(src, action)
					actions[#actions + 1] = { src = src, action = action }
				end)
				reg:all()[1].playback.volume:set_perc(70)
				assert.equals(1, #actions)
				assert.equals(registry.PlaybackAction.SetVolume, actions[1].action)
			end)

			it("adjust_perc clamps at 100", function()
				local exec, vol_exec, vol_calls = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", { volume = 92 }, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				reg:all()[1].playback.volume:adjust_perc(15)
				assert.equals(1, #vol_calls)
				assert.equals(100, vol_calls[1].pct)
			end)

			it("adjust_perc clamps at 0", function()
				local exec, vol_exec, vol_calls = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", { volume = 5 }, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				reg:all()[1].playback.volume:adjust_perc(-20)
				assert.equals(1, #vol_calls)
				assert.equals(0, vol_calls[1].pct)
			end)

			it("adjust_perc uses 0 as current when state.volume is nil", function()
				local exec, vol_exec, vol_calls = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", {}, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				reg:all()[1].playback.volume:adjust_perc(10)
				assert.equals(1, #vol_calls)
				assert.equals(10, vol_calls[1].pct)
			end)

			it("r.update with can_set_volume=false nil-ifies playback.volume", function()
				local exec, vol_exec = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", {}, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				assert.is_table(reg:all()[1].playback.volume)
				registrar.update("src:1", {}, { can_set_volume = false })
				assert.is_nil(reg:all()[1].playback.volume)
			end)

			it("volume has toggle_mute function", function()
				local exec, vol_exec = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", { volume = 50 }, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				assert.is_function(reg:all()[1].playback.volume.toggle_mute)
			end)

			it("toggle_mute when volume > 0 sets volume to 0", function()
				local exec, vol_exec, vol_calls = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", { volume = 75 }, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				reg:all()[1].playback.volume:toggle_mute()
				assert.equals(1, #vol_calls)
				assert.equals(0, vol_calls[1].pct)
			end)

			it("toggle_mute when volume == 0 restores cached pre-mute volume", function()
				local exec, vol_exec, vol_calls = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", { volume = 60 }, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				local vol = reg:all()[1].playback.volume
				vol:toggle_mute() -- mute: saves 60, sets 0
				registrar.update("src:1", { volume = 0 }) -- simulate state arriving
				vol:toggle_mute() -- unmute: restores 60
				assert.equals(2, #vol_calls)
				assert.equals(60, vol_calls[2].pct)
			end)

			it("toggle_mute when volume == 0 and no cache restores to 100", function()
				local exec, vol_exec, vol_calls = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", { volume = 0 }, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				reg:all()[1].playback.volume:toggle_mute()
				assert.equals(1, #vol_calls)
				assert.equals(100, vol_calls[1].pct)
			end)

			it("toggle_mute fires on_playback_action with ToggleMute", function()
				local exec, vol_exec = make_executor(), make_vol_executor()
				registrar.add("src:1", "source", { volume = 50 }, {
					playback = exec,
					volume = vol_exec,
					flags = make_flags(),
				})
				local actions = {}
				reg.on_playback_action(function(_, action)
					actions[#actions + 1] = action
				end)
				reg:all()[1].playback.volume:toggle_mute()
				assert.equals(1, #actions)
				assert.equals(registry.PlaybackAction.ToggleMute, actions[1])
			end)
		end)
	end)

	describe("unsubscribe", function()
		it("on_added returns a function", function()
			local unsub = reg:on_added(function() end)
			assert.is_function(unsub)
		end)

		it("unsubscribing on_added stops callback from firing on subsequent adds", function()
			local count = 0
			local unsub = reg:on_added(function()
				count = count + 1
			end)
			registrar.add("src:1", "source", {})
			unsub()
			registrar.add("src:2", "source", {})
			assert.equals(1, count)
		end)

		it("on_updated returns a function", function()
			local unsub = reg:on_updated(function() end)
			assert.is_function(unsub)
		end)

		it("unsubscribing on_updated stops callback from firing on subsequent updates", function()
			registrar.add("src:1", "source", {})
			local count = 0
			local unsub = reg:on_updated(function()
				count = count + 1
			end)
			registrar.update("src:1", { title = "A" })
			unsub()
			registrar.update("src:1", { title = "B" })
			assert.equals(1, count)
		end)

		it("on_removed returns a function", function()
			local unsub = reg:on_removed(function() end)
			assert.is_function(unsub)
		end)

		it("unsubscribing on_removed stops callback from firing on subsequent removes", function()
			registrar.add("src:1", "source", {})
			registrar.add("src:2", "source", {})
			local count = 0
			local unsub = reg:on_removed(function()
				count = count + 1
			end)
			registrar.remove("src:1")
			unsub()
			registrar.remove("src:2")
			assert.equals(1, count)
		end)

		it("on_updated (debounced) returns a function", function()
			local unsub = reg:on_updated(function() end, { debounce = 0.2 })
			assert.is_function(unsub)
		end)

		it("unsubscribing debounced on_updated stops callback from firing", function()
			local gears_mod = require("gears")
			gears_mod._created = {}
			registrar.add("src:1", "source", {})
			local count = 0
			local unsub = reg:on_updated(function()
				count = count + 1
			end, { debounce = 0.2 })
			registrar.update("src:1", { title = "X" }) -- creates timer
			assert.equals(1, #gears_mod._created)
			unsub()
			-- Observable does not stop the timer on unsub; the pool becomes empty
			-- and the callback guard prevents the callback from firing when the timer fires.
			gears_mod._created[1]:fire()
			assert.equals(0, count)
		end)

		it("unsubscribing debounced on_updated with no pending timer is a no-op", function()
			registrar.add("src:1", "source", {})
			local unsub = reg:on_updated(function() end, { debounce = 0.2 })
			assert.has_no.errors(function()
				unsub()
			end)
		end)

		it("on_playback_action returns a function", function()
			local unsub = reg.on_playback_action(function() end)
			assert.is_function(unsub)
		end)

		it("unsubscribing on_playback_action stops callback from firing on subsequent actions", function()
			local exec = {
				play = function(_id) end,
				pause = function(_id) end,
				play_pause = function(_id) end,
				stop = function(_id) end,
				next = function(_id) end,
				previous = function(_id) end,
				seek = function(_id, _s) end,
				set_position = function(_id, _s) end,
			}
			local flags = {
				can_control = true,
				can_seek = true,
				can_go_next = true,
				can_go_previous = true,
				can_play = true,
				can_pause = true,
			}
			registrar.add("src:1", "source", {}, { playback = exec, flags = flags })
			local count = 0
			local unsub = reg.on_playback_action(function()
				count = count + 1
			end)
			reg:all()[1].playback:play()
			unsub()
			reg:all()[1].playback:play()
			assert.equals(1, count)
		end)
	end)

	describe("debounce", function()
		local gears_mod

		before_each(function()
			gears_mod = require("gears")
			gears_mod._created = {} -- reset timer list between tests
			reg, registrar = registry.new()
			registrar.add("src:1", "source", { title = "Track" })
		end)

		it("opts = nil behaves identically to non-debounced (fires immediately)", function()
			local called = 0
			reg:on_updated(function()
				called = called + 1
			end, nil)
			registrar.update("src:1", { title = "Updated" })
			assert.equals(1, called)
			assert.equals(0, #gears_mod._created) -- no timer created
		end)

		it("debounced callback not called immediately on update", function()
			local called = false
			reg:on_updated(function()
				called = true
			end, { debounce = 0.2 })
			registrar.update("src:1", { title = "Updated" })
			assert.is_false(called)
		end)

		it("debounced callback fires after timer with latest state", function()
			local received
			reg:on_updated(function(s)
				received = s
			end, { debounce = 0.2 })
			registrar.update("src:1", { title = "First" })
			registrar.update("src:1", { title = "Second" })
			-- two updates -> one timer (reset via :again()), not two timers
			assert.equals(1, #gears_mod._created)
			gears_mod._created[1]:fire()
			assert.is_not_nil(received)
			assert.equals("Second", received.state.title)
		end)

		it("two debounced subscriptions with different intervals fire independently", function()
			local calls_a, calls_b = 0, 0
			reg:on_updated(function()
				calls_a = calls_a + 1
			end, { debounce = 0.1 })
			reg:on_updated(function()
				calls_b = calls_b + 1
			end, { debounce = 0.5 })
			registrar.update("src:1", { title = "X" })
			assert.equals(2, #gears_mod._created) -- one timer per subscription
			gears_mod._created[1]:fire()
			assert.equals(1, calls_a)
			assert.equals(0, calls_b)
			gears_mod._created[2]:fire()
			assert.equals(1, calls_a)
			assert.equals(1, calls_b)
		end)

		it("position-only update when no timer pending: no timer started", function()
			local called = false
			reg:on_updated(function()
				called = true
			end, { debounce = 0.2 })
			registrar.update("src:1", { position = 10.0 })
			assert.equals(0, #gears_mod._created)
			assert.is_false(called)
		end)

		it("position-only update when timer pending: does not reset the timer", function()
			reg:on_updated(function() end, { debounce = 0.2 })
			registrar.update("src:1", { title = "X" }) -- non-position: creates timer
			assert.equals(1, #gears_mod._created)
			local t = gears_mod._created[1]
			registrar.update("src:1", { position = 99.0 }) -- position-only: must NOT call :again()
			assert.equals(0, t.again_count)
		end)

		it("empty partial_state is a no-op: no callbacks fired, no timer started", function()
			local called = false
			reg:on_updated(function()
				called = true
			end, { debounce = 0.2 })
			registrar.update("src:1", {})
			assert.equals(0, #gears_mod._created)
			assert.is_false(called)
		end)

		it("non-position update resets an already-pending timer via :again()", function()
			reg:on_updated(function() end, { debounce = 0.2 })
			registrar.update("src:1", { title = "First" }) -- creates timer
			local t = gears_mod._created[1]
			registrar.update("src:1", { title = "Second" }) -- must call :again(), not create new timer
			assert.equals(1, t.again_count)
			assert.equals(1, #gears_mod._created) -- still only one timer instance
		end)

		it("source removal stops pending timer and callback does not fire after remove", function()
			local called = false
			reg:on_updated(function()
				called = true
			end, { debounce = 0.2 })
			registrar.update("src:1", { title = "X" })
			local t = gears_mod._created[1]
			registrar.remove("src:1")
			assert.is_true(t.stopped)
			-- Simulate OS timer race: timer fires after source was removed.
			-- The callback guard (observable:get(id) nil check) suppresses the call.
			t:fire()
			assert.is_false(called)
		end)

		it("non-debounced subscriptions unaffected when debounced ones coexist", function()
			local immediate_calls = 0
			reg:on_updated(function()
				immediate_calls = immediate_calls + 1
			end)
			reg:on_updated(function() end, { debounce = 0.2 })
			registrar.update("src:1", { title = "X" })
			assert.equals(1, immediate_calls)
		end)
	end)

	describe("source:subscribe", function()
		local gears_mod
		local source

		before_each(function()
			gears_mod = require("gears")
			gears_mod._created = {}
			reg, registrar = registry.new()
			registrar.add("src:1", "source", { title = "Track A", status = "playing" })
			source = reg:all()[1]
		end)

		it("fires immediately on update when no opts provided", function()
			local calls = {}
			source:subscribe(function(s)
				calls[#calls + 1] = s
			end)
			registrar.update("src:1", { title = "Track B" })
			assert.equals(1, #calls)
			assert.equals("Track B", calls[1].title)
		end)

		it("returns an unsubscribe function that stops further calls", function()
			local count = 0
			local unsub = source:subscribe(function()
				count = count + 1
			end)
			registrar.update("src:1", { title = "B" })
			unsub()
			registrar.update("src:1", { title = "C" })
			assert.equals(1, count)
		end)

		it("debounced: does not fire immediately on update", function()
			local called = false
			source:subscribe(function()
				called = true
			end, { debounce = 0.1 })
			registrar.update("src:1", { title = "Track B" })
			assert.is_false(called)
		end)

		it("debounced: fires after timer expires", function()
			local calls = {}
			source:subscribe(function(s)
				calls[#calls + 1] = s
			end, { debounce = 0.1 })
			registrar.update("src:1", { title = "Track B" })
			assert.equals(1, #gears_mod._created)
			gears_mod._created[1]:fire()
			assert.equals(1, #calls)
			assert.equals("Track B", calls[1].title)
		end)

		it("debounced: multiple updates restart the timer (coalesced)", function()
			source:subscribe(function() end, { debounce = 0.1 })
			registrar.update("src:1", { title = "B" })
			registrar.update("src:1", { title = "C" })
			registrar.update("src:1", { title = "D" })
			assert.equals(1, #gears_mod._created)
			assert.equals(3, gears_mod._created[1].again_count)
		end)

		it("debounced: unsubscribe prevents callback from firing", function()
			local count = 0
			local unsub = source:subscribe(function()
				count = count + 1
			end, { debounce = 0.1 })
			registrar.update("src:1", { title = "B" })
			unsub()
			-- Pool is empty after unsub; timer may still fire but callback is suppressed.
			gears_mod._created[1]:fire()
			assert.equals(0, count)
		end)
	end)

	describe("source:active()", function()
		it("returns true when state has a title", function()
			registrar.add("src:1", "test", { title = "Some Track" })
			local source = reg:all()[1]
			assert.is_true(source:active())
		end)

		it("returns true when status is playing and no title", function()
			registrar.add("src:1", "test", { status = "playing" })
			local source = reg:all()[1]
			assert.is_true(source:active())
		end)

		it("returns false when no title and status is paused", function()
			registrar.add("src:1", "test", { status = "paused" })
			local source = reg:all()[1]
			assert.is_false(source:active())
		end)

		it("returns false when no title and no status", function()
			registrar.add("src:1", "test", {})
			local source = reg:all()[1]
			assert.is_false(source:active())
		end)

		it("returns true when both title and playing", function()
			registrar.add("src:1", "test", { title = "Track", status = "playing" })
			local source = reg:all()[1]
			assert.is_true(source:active())
		end)
	end)

	describe("PlaybackAction", function()
		it("is a table on the registry module", function()
			assert.is_table(registry.PlaybackAction)
		end)

		it("contains all expected action keys", function()
			assert.equals("play", registry.PlaybackAction.Play)
			assert.equals("pause", registry.PlaybackAction.Pause)
			assert.equals("play_pause", registry.PlaybackAction.PlayPause)
			assert.equals("stop", registry.PlaybackAction.Stop)
			assert.equals("next", registry.PlaybackAction.Next)
			assert.equals("previous", registry.PlaybackAction.Previous)
			assert.equals("seek", registry.PlaybackAction.Seek)
			assert.equals("set_position", registry.PlaybackAction.SetPosition)
		end)
	end)

	describe("on_playback_action", function()
		it("returns an unsubscribe function", function()
			local unsub = reg.on_playback_action(function() end)
			assert.is_function(unsub)
		end)

		it("callback not yet called after registration (no actions fired)", function()
			local called = false
			reg.on_playback_action(function()
				called = true
			end)
			assert.is_false(called)
		end)
	end)

	describe("MediaSource events", function()
		local function make_executor()
			return {
				play = function() end,
				pause = function() end,
				play_pause = function() end,
				stop = function() end,
				next = function() end,
				previous = function() end,
				seek = function() end,
				set_position = function() end,
			}
		end

		describe("subscribe", function()
			it("returns an unsub function", function()
				registrar.add("src:1", "source", {})
				local source = reg:all()[1]
				local unsub = source:subscribe(function() end)
				assert.is_function(unsub)
			end)

			it("delivers state updates to subscriber", function()
				registrar.add("src:1", "source", {})
				local source = reg:all()[1]
				local received
				source:subscribe(function(s)
					received = s
				end)
				registrar.update("src:1", { title = "Track" })
				assert.equals("Track", received.title)
			end)

			it("unsub stops delivery", function()
				registrar.add("src:1", "source", {})
				local source = reg:all()[1]
				local calls = 0
				local unsub = source:subscribe(function()
					calls = calls + 1
				end)
				registrar.update("src:1", { title = "A" })
				unsub()
				registrar.update("src:1", { title = "B" })
				assert.equals(1, calls)
			end)
		end)

		describe("on_removed", function()
			it("fires callback with source_id on remove", function()
				registrar.add("src:1", "source", {})
				local source = reg:all()[1]
				local received_id
				source:on_removed(function(id)
					received_id = id
				end)
				registrar.remove("src:1")
				assert.equals("src:1", received_id)
			end)

			it("does not fire again on a second remove (no-op)", function()
				registrar.add("src:1", "source", {})
				local source = reg:all()[1]
				local calls = 0
				source:on_removed(function()
					calls = calls + 1
				end)
				registrar.remove("src:1")
				registrar.remove("src:1")
				assert.equals(1, calls)
			end)
		end)

		describe("active", function()
			it("returns false for a source with empty state", function()
				registrar.add("src:1", "source", {})
				local source = reg:all()[1]
				assert.is_false(source:active())
			end)

			it("returns true when title is set", function()
				registrar.add("src:1", "source", { title = "Song" })
				local source = reg:all()[1]
				assert.is_true(source:active())
			end)

			it("returns true when status is playing (no title)", function()
				registrar.add("src:1", "source", { status = "playing" })
				local source = reg:all()[1]
				assert.is_true(source:active())
			end)
		end)

		describe("on_control", function()
			it("fires with source state when a playback action dispatches", function()
				registrar.add("src:1", "source", { title = "T" }, {
					playback = make_executor(),
					flags = { can_control = true, can_play = true, can_pause = true },
				})
				local source = reg:all()[1]
				local received
				source:on_control(function(s)
					received = s
				end)
				source.playback:play()
				assert.equals("T", received.title)
			end)
		end)
	end)
end)
