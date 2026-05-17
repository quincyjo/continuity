require("spec.support.awesome_mocks")

-- Mock art and notification to isolate init.lua wiring
package.preload["continuity.media.art"] = function()
	return {
		resolve = function(_, cb)
			cb(nil)
		end,
		_clear_cache = function() end,
	}
end

local notifications_fired = {}
local signal_handlers = {}
local naughty = require("naughty")
naughty.notification = function(opts)
	local n = naughty.make_notification(opts)
	notifications_fired[#notifications_fired + 1] = n
	return n
end
naughty.connect_signal = function(name, cb)
	signal_handlers[name] = signal_handlers[name] or {}
	signal_handlers[name][#signal_handlers[name] + 1] = cb
end
naughty.notification_closed_reason = { dismissed_by_command = "dismissed_by_command" }

describe("media module", function()
	-- Reload media fresh for each test to avoid module-level _registry state
	local function fresh_media()
		package.loaded["continuity.media"] = nil
		package.loaded["continuity.media.registry"] = nil
		package.loaded["continuity.media.notification"] = nil
		package.loaded["continuity.media.coalescer"] = nil
		signal_handlers = {}
		return require("continuity.media")
	end

	before_each(function()
		notifications_fired = {}
	end)

	it("setup() calls backend:start with a registrar", function()
		local media = fresh_media()
		local started_with
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				started_with = reg
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		assert.is_not_nil(started_with)
		assert.is_function(started_with.add)
		assert.is_function(started_with.update)
		assert.is_function(started_with.remove)
	end)

	it("on_source_added callback is not replayed for sources added before subscription", function()
		local media = fresh_media()
		local added
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", { title = "Track", status = "playing", uri = "x:1" })
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		media.sources:on_added(function(s)
			added = s
		end)
		-- sources.on_added fires retroactively for already-known sources? No —
		-- sources.all() provides the snapshot; callbacks are for future events.
		assert.is_nil(added) -- callback registered after setup; prior add not replayed
	end)

	it("sources.all() returns already-registered sources", function()
		local media = fresh_media()
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", { title = "Track" })
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		local sources = media.sources:all()
		assert.equals(1, #sources)
		assert.equals("fake:1", sources[1].id)
	end)

	it("sources.get() returns the source for a known id", function()
		local media = fresh_media()
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", { title = "Track" })
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		local source = media.sources:get("fake:1")
		assert.is_not_nil(source)
		assert.equals("fake:1", source.id)
	end)

	it("sources.get() returns nil for an unknown id", function()
		local media = fresh_media()
		local fake_backend = {
			name = "fake",
			start = function(_self, _reg) end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		assert.is_nil(media.sources:get("does_not_exist"))
	end)

	it("sources.get() returns nil before setup", function()
		local media = fresh_media()
		assert.is_nil(media.sources:get("any"))
	end)

	it("notification fires when backend adds a playing source", function()
		local media = fresh_media()
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", { title = "Song", status = "playing", uri = "x:1" })
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		assert.equals(1, #notifications_fired)
	end)

	it("sources.on_added returns an unsubscribe function", function()
		local media = fresh_media()
		media.setup({ backends = {} })
		local unsub = media.sources:on_added(function() end)
		assert.is_function(unsub)
	end)

	it("sources.on_updated returns an unsubscribe function", function()
		local media = fresh_media()
		media.setup({ backends = {} })
		local unsub = media.sources:on_updated(function() end)
		assert.is_function(unsub)
	end)

	it("sources.on_removed returns an unsubscribe function", function()
		local media = fresh_media()
		media.setup({ backends = {} })
		local unsub = media.sources:on_removed(function() end)
		assert.is_function(unsub)
	end)

	it("setup() errors on second call", function()
		local media = fresh_media()
		media.setup({ backends = {} })
		assert.has_error(function()
			media.setup({ backends = {} })
		end)
	end)

	it("setup() always registers 'added' signal handler", function()
		local media = fresh_media()
		media.setup({ backends = {} })
		assert.is_not_nil(signal_handlers["added"])
		assert.is_true(#signal_handlers["added"] >= 1)
	end)

	it("notifications=false suppresses all notification hooks — no notification fires", function()
		local media = fresh_media()
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", { title = "Song", status = "playing" })
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend }, notifications = false })
		assert.equals(0, #notifications_fired)
	end)

	it("setup() with sources wires coalescer — configured backend id maps to unified id", function()
		local media = fresh_media()
		local reg_seen
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg_seen = reg
			end,
			stop = function(_self) end,
		}
		media.setup({
			backends = { fake_backend },
			sources = {
				{ id = "unified", backends = { "raw:1" } },
			},
		})
		local added_id
		media.sources:on_added(function(s)
			added_id = s.id
		end)
		reg_seen.add("raw:1", "raw", { title = "T" })
		assert.equals("unified", added_id)
	end)

	it("position activation wires end-to-end through coalescer", function()
		local media = fresh_media()
		local position_cb_for = {}

		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", { status = "playing" }, {
					position = {
						subscribe = function(_source_id, cb)
							position_cb_for["fake:1"] = cb
							return function() end
						end,
						get = function(_source_id, cb)
							cb(nil)
						end,
					},
				})
			end,
			stop = function(_self) end,
		}

		media.setup({
			backends = { fake_backend },
			sources = { { id = "unified", backends = { "fake:1" } } },
		})

		local src = media.sources:all()[1]
		assert.is_not_nil(src)
		local received = {}
		src.position:subscribe(function(p)
			received[#received + 1] = p
		end)

		position_cb_for["fake:1"](12.5)

		assert.equals(1, #received)
		assert.is_near(12.5, received[1], 0.001)
	end)

	it("source.position.get returns nil when backend has no position caps", function()
		local media = fresh_media()
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", {})
			end,
			stop = function(_self) end,
		}
		media.setup({
			backends = { fake_backend },
			sources = { { id = "unified", backends = { "fake:1" } } },
		})
		local src = media.sources:all()[1]
		local result = "not_called"
		src.position:get(function(p)
			result = p
		end)
		assert.is_nil(result)
	end)

	it("no-coalescer: source.playback dispatches via executor when backend supports it", function()
		local media = fresh_media()
		local playback_cmds = {}
		-- Executor: first arg is source_id
		local playback_executor = {
			play = function(id)
				playback_cmds[#playback_cmds + 1] = { action = "play", id = id }
			end,
			pause = function() end,
			play_pause = function() end,
			stop = function() end,
			next = function() end,
			previous = function() end,
			seek = function() end,
			set_position = function() end,
		}
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", {}, {
					playback = playback_executor,
					flags = { can_control = true, can_play = true, can_pause = true },
				})
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		local src = media.sources:all()[1]
		assert.is_table(src.playback)
		assert.is_function(src.playback.play)
		src.playback:play()
		assert.equals(1, #playback_cmds)
		assert.equals("play", playback_cmds[1].action)
		assert.equals("fake:1", playback_cmds[1].id)
	end)

	it("no-coalescer: source.playback is nil when backend has no playback", function()
		local media = fresh_media()
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg.add("fake:1", "fake", {})
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		assert.is_nil(media.sources:all()[1].playback)
	end)

	it("exports PlaybackAction enum", function()
		local media = fresh_media()
		assert.is_table(media.PlaybackAction)
		assert.equals("previous", media.PlaybackAction.Previous)
	end)

	it("no-coalescer: push_position from registry.update notifies position subscribers", function()
		local media = fresh_media()
		local reg_seen
		local fake_backend = {
			name = "fake",
			start = function(_self, reg)
				reg_seen = reg
				reg.add("fake:1", "fake", {}, {
					playback = {
						play = function() end,
						pause = function() end,
						play_pause = function() end,
						stop = function() end,
						next = function() end,
						previous = function() end,
						seek = function() end,
						set_position = function() end,
					},
				})
			end,
			stop = function(_self) end,
		}
		media.setup({ backends = { fake_backend } })
		local src = media.sources:all()[1]
		local received_pos
		src.position:subscribe(function(p)
			received_pos = p
		end)
		-- Backend pushes position via registry.update
		reg_seen.update("fake:1", { position = 42.5 })
		assert.is_near(42.5, received_pos, 0.001)
	end)
end)
