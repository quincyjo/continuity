require("spec.support.awesome_mocks")

local naughty = require("naughty")
local notifications_fired = {}
local added_handlers = {}

-- Override naughty stubs for notification-specific behaviour.
naughty.notification = function(opts)
	local notif = naughty.make_notification(opts)
	notifications_fired[#notifications_fired + 1] = notif
	return notif
end

naughty.connect_signal = function(name, cb)
	if name == "added" then
		added_handlers[#added_handlers + 1] = cb
	end
end

-- Helper: manually fire the "added" signal in tests.
local function fire_added(notif, args)
	for _, h in ipairs(added_handlers) do
		h(notif, args)
	end
end

-- Mock art: synchronous by default; set art_deferred=true to capture callbacks
-- for manual flushing (simulates async art resolve in race-condition tests).
local art_deferred = false
local pending_art_callbacks = {}

local function flush_art()
	local cbs = pending_art_callbacks
	pending_art_callbacks = {}
	for _, cb in ipairs(cbs) do
		cb(nil)
	end
end

local function flush_art_reverse()
	local cbs = pending_art_callbacks
	pending_art_callbacks = {}
	for i = #cbs, 1, -1 do
		cbs[i](nil)
	end
end

package.preload["continuity.media.art"] = function()
	return {
		resolve = function(_uri, cb)
			if art_deferred then
				pending_art_callbacks[#pending_art_callbacks + 1] = cb
			else
				cb(nil)
			end
		end,
		_clear_cache = function() end,
		_inject_cache = function() end,
	}
end

local function make_mock_registry()
	local r = {
		_added_cbs = {},
		_updated_cbs = {},
		_removed_cbs = {},
		_playback_cbs = {},
	}
	r.on_source_added = function(cb)
		r._added_cbs[#r._added_cbs + 1] = cb
	end
	r.on_source_updated = function(cb)
		r._updated_cbs[#r._updated_cbs + 1] = cb
	end
	r.on_source_removed = function(cb)
		r._removed_cbs[#r._removed_cbs + 1] = cb
	end
	r.on_playback_action = function(cb)
		r._playback_cbs[#r._playback_cbs + 1] = cb
	end
	r.fire_updated = function(s)
		for _, cb in ipairs(r._updated_cbs) do
			cb(s)
		end
	end
	r.fire_added = function(s)
		for _, cb in ipairs(r._added_cbs) do
			cb(s)
		end
	end
	r.fire_removed = function(id)
		for _, cb in ipairs(r._removed_cbs) do
			cb(id)
		end
	end
	r.fire_playback = function(s, a)
		for _, cb in ipairs(r._playback_cbs) do
			cb(s, a)
		end
	end
	return r
end

local notification = require("continuity.media.notification")

describe("notification", function()
	before_each(function()
		notifications_fired = {}
		added_handlers = {}
		art_deferred = false
		pending_art_callbacks = {}
	end)

	local function make_source(id, state)
		return {
			id = id,
			name = id,
			state = state or {},
			active = function(self)
				return self.state.title ~= nil or self.state.status == "playing"
			end,
		}
	end

	-- Helper: fake D-Bus notification object.
	local function make_dbus_notif()
		local n = { ignore = false, _private = { is_destroyed = false } }
		n.destroy = function(self)
			self._private.is_destroyed = true
		end
		n.connect_signal = function(_self, _name, _cb) end
		return n
	end

	describe("change detection", function()
		it("fires on first playing track", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", {
				title = "Song",
				artist = "Artist",
				status = "playing",
			}))
			assert.equals(1, #notifications_fired)
		end)

		it("does not re-fire for same title and artist", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			local source = make_source("mpris:spotify", {
				title = "Song",
				artist = "Artist",
				status = "playing",
			})
			mock_reg.fire_updated(source)
			mock_reg.fire_updated(source)
			assert.equals(1, #notifications_fired)
		end)

		it("fires again when title changes", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song A", status = "playing" }))
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song B", status = "playing" }))
			assert.equals(2, #notifications_fired)
		end)

		it("uses title|artist as identity", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpd:localhost", {
				title = "Song A",
				artist = "Artist",
				status = "playing",
			}))
			mock_reg.fire_updated(make_source("mpd:localhost", {
				title = "Song B",
				artist = "Artist",
				status = "playing",
			}))
			assert.equals(2, #notifications_fired)
		end)

		it("does not fire when status is not playing", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpd:localhost", {
				title = "Song",
				artist = "Artist",
				status = "paused",
			}))
			assert.equals(0, #notifications_fired)
		end)

		it("does not fire when status is nil", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpd:localhost", { title = "Song" }))
			assert.equals(0, #notifications_fired)
		end)

		it("destroys notifcations for a source that goes inactive", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpd:localhost", { title = "Song", status = "playing" }))
			assert.equals(1, #notifications_fired)
			mock_reg.fire_updated(make_source("mpd:localhost", { title = nil, status = "stopped" }))
			local notif = notifications_fired[1]
			assert.is_true(notif._private.is_destroyed)
		end)
	end)

	describe("default_callback", function()
		it("uses source playback title as title", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", {
				title = "Song",
				artist = "Artist",
				status = "playing",
			}))
			assert.equals("Song", notifications_fired[1].opts.title)
		end)

		it("formats with both title and artist", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", {
				title = "Song",
				artist = "Artist",
				status = "playing",
			}))
			assert.equals("Song", notifications_fired[1].opts.title)
			assert.equals("Artist", notifications_fired[1].opts.message)
		end)

		it("falls back to Unknown for nil artist", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song", status = "playing" }))
			assert.equals("Song", notifications_fired[1].opts.title)
			assert.equals("Unknown", notifications_fired[1].opts.message)
		end)

		it("sets timeout to 6", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song", status = "playing" }))
			assert.equals(6, notifications_fired[1].opts.timeout)
		end)
	end)

	describe("notify_callback (opts table style)", function()
		it("uses returned args for notification", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, {
				notify_callback = function(_source, _icon)
					return { title = "custom", message = "custom msg" }
				end,
			})
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song", status = "playing" }))
			assert.equals("custom", notifications_fired[1].opts.title)
			assert.equals("custom msg", notifications_fired[1].opts.message)
		end)

		it("suppresses notification when callback returns nil", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, {
				notify_callback = function(_source, _icon)
					return nil
				end,
			})
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song", status = "playing" }))
			assert.equals(0, #notifications_fired)
		end)

		it("receives the source object and resolved icon", function()
			local received_source, received_icon
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, {
				notify_callback = function(source, icon)
					received_source = source
					received_icon = icon
					return { title = "t" }
				end,
			})
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song", status = "playing" }))
			assert.equals("mpris:spotify", received_source.id)
			assert.is_nil(received_icon) -- art mock resolves nil
		end)
	end)

	describe("notification replacement", function()
		it("destroys previous notification for same source before creating new one", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song A", status = "playing" }))
			local first = notifications_fired[1]
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song B", status = "playing" }))
			assert.is_true(first._private.is_destroyed)
			assert.equals(2, #notifications_fired)
		end)

		it("does not destroy notification from a different source", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song", status = "playing" }))
			local first = notifications_fired[1]
			mock_reg.fire_updated(make_source("mpris:vlc", { title = "Other", status = "playing" }))
			assert.is_false(first._private.is_destroyed)
		end)

		it("does not create a stale notification when art resolves out of order", function()
			-- Regression: art.resolve is async. If the user skips tracks quickly, two
			-- create_notification calls are in-flight simultaneously. The older callback
			-- must not create a notification after the newer one has already fired.
			-- Without the captured_identity guard, the stale callback sees
			-- identity(source.state) == last_identity (both advanced to Song B) and
			-- incorrectly passes the guard, creating a duplicate notification.
			art_deferred = true
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			local source = make_source("mpris:spotify", { title = "Song A", status = "playing" })
			mock_reg.fire_updated(source) -- art cb #1 queued (captured_identity = A)
			source.state.title = "Song B"
			mock_reg.fire_updated(source) -- art cb #2 queued (captured_identity = B); last_identity = B
			-- Resolve in reverse: Song B's callback fires first (correct notification),
			-- then Song A's stale callback fires and must bail.
			flush_art_reverse()
			assert.equals(1, #notifications_fired)
			assert.equals("Song B", notifications_fired[1].opts.title)
			assert.equals("Unknown", notifications_fired[1].opts.message)
		end)
	end)

	describe("on_source_removed", function()
		it("clears identity so re-added source fires a fresh notification", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", {
				title = "Song",
				artist = "Artist",
				status = "playing",
			}))
			mock_reg.fire_removed("mpris:spotify")
			mock_reg.fire_updated(make_source("mpris:spotify", {
				title = "Song",
				artist = "Artist",
				status = "playing",
			}))
			assert.equals(2, #notifications_fired)
		end)

		--[[ Currently have it destroying existing notifications on source removed.
		it("clears last_notif so re-added source does not destroy the previous notification", function()
			-- Verifies last_notif[source_id] = nil is part of the cleanup.
			-- Without it, the re-add would find the old notif in last_notif and destroy it.
			local n = notification.new(nil)
			n.on_source_updated(make_source("mpris:spotify", { title = "Song A", status = "playing" }))
			local first_notif = notifications_fired[1]
			n.on_source_removed("mpris:spotify")
			-- Re-add same track: last_notif is cleared, so no destroy of the first notification.
			n.on_source_updated(make_source("mpris:spotify", { title = "Song A", status = "playing" }))
			assert.is_false(first_notif._private.is_destroyed)
			assert.equals(2, #notifications_fired)
		end)
        ]]
	end)

	describe("D-Bus suppression", function()
		it("always registers 'added' signal handler", function()
			notification.new(make_mock_registry(), nil)
			assert.equals(1, #added_handlers)
		end)

		it("suppresses D-Bus notification matching current_title (MPRIS first)", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			-- on_source_updated with status="stopped" registers the source without firing
			-- a notification or setting current_title (status guard skips both).
			mock_reg.fire_updated(make_source("spotify", { status = "stopped" }))
			-- MPRIS moves to playing: current_title is set at the top of on_source_updated.
			mock_reg.fire_updated(make_source("spotify", { title = "Song A", status = "playing" }))
			local dbus = make_dbus_notif()
			fire_added(dbus, { freedesktop_hints = {}, title = "Song A" })
			assert.is_true(dbus.ignore)
			assert.is_true(dbus._private.is_destroyed)
		end)

		it("suppresses D-Bus notification matching last_notified_title", function()
			-- Use deferred art so we can advance current_title (via on_source_updated for
			-- Song B) while last_notified_title still holds Song A (create_notification for
			-- B has not resolved yet).  This models the MPRIS-B-first / D-Bus-A-late race.
			art_deferred = true
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("spotify", { title = "Song A", status = "playing" }))
			flush_art() -- resolves Song A's art; last_notified_title = "Song A"
			-- MPRIS moves to Song B: current_title = "Song B", art for B deferred.
			mock_reg.fire_updated(make_source("spotify", { title = "Song B", status = "playing" }))
			-- last_notified_title is still "Song A"; D-Bus for Song A must be suppressed.
			local dbus = make_dbus_notif()
			fire_added(dbus, { freedesktop_hints = {}, title = "Song A" })
			assert.is_true(dbus.ignore)
			assert.is_true(dbus._private.is_destroyed)
			flush_art() -- cleanup pending callback
		end)

		it("parks D-Bus notification for deferred suppression (D-Bus arrives before MPRIS)", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			-- Source must be registered before D-Bus can be parked against it.
			mock_reg.fire_updated(make_source("spotify", { status = "stopped" }))
			local dbus = make_dbus_notif()
			-- D-Bus arrives before MPRIS title update: parked.
			fire_added(dbus, { freedesktop_hints = {}, title = "Song B" })
			assert.is_false(dbus._private.is_destroyed)
			-- MPRIS update fires: current_title set at top of on_source_updated destroys
			-- the parked notification before our own notification is created.
			mock_reg.fire_updated(make_source("spotify", { title = "Song B", status = "playing" }))
			assert.is_true(dbus._private.is_destroyed)
		end)

		it("does not park D-Bus notification when no sources are tracked", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			-- No lifecycle call: tracked_sources is empty.
			local dbus = make_dbus_notif()
			fire_added(dbus, { freedesktop_hints = {}, title = "Some Song" })
			assert.is_false(dbus._private.is_destroyed)
			-- A subsequent on_source_updated with matching title must NOT destroy it (not parked).
			mock_reg.fire_updated(make_source("spotify", { title = "Some Song", status = "playing" }))
			assert.is_false(dbus._private.is_destroyed)
		end)

		it("does not suppress non-freedesktop notifications (our own naughty.notification calls)", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			-- Populate tracked_sources and current_title so the freedesktop_hints check is
			-- the actual discriminator, not a vacuously-empty tracked_sources loop.
			mock_reg.fire_updated(make_source("spotify", { status = "stopped" }))
			mock_reg.fire_updated(make_source("spotify", { title = "Song A", status = "playing" }))
			-- make_dbus_notif() is reused for its bare notification structure; this object
			-- represents an internal naughty.notification (no freedesktop_hints), not a D-Bus one.
			local our_notif = make_dbus_notif()
			-- No freedesktop_hints: handler must return early before checking the title.
			fire_added(our_notif, { title = "Song A" })
			assert.is_false(our_notif.ignore)
			assert.is_false(our_notif._private.is_destroyed)
		end)

		it("clears tracked_ids so removed source is no longer suppressed", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			mock_reg.fire_updated(make_source("mpris:spotify", { title = "Song A", status = "playing" }))
			mock_reg.fire_removed("mpris:spotify")
			-- D-Bus notification with the previously playing title must not be suppressed.
			local dbus = make_dbus_notif()
			fire_added(dbus, { freedesktop_hints = {}, title = "Song A" })
			assert.is_false(dbus.ignore)
			assert.is_false(dbus._private.is_destroyed)
		end)
	end)

	describe("on_playback_action", function()
		it("refreshes notification when previous is called and identity unchanged (restart case)", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			local source = make_source("mpris:spotify", { title = "Song A", status = "playing" })
			mock_reg.fire_updated(source)
			assert.equals(1, #notifications_fired)
			local reset_count = 0
			notifications_fired[1].reset_timeout = function(_self)
				reset_count = reset_count + 1
			end
			-- Same identity: simulate restart — refreshes (resets timeout), no new notification
			mock_reg.fire_playback(source, "previous")
			assert.equals(1, #notifications_fired)
			assert.equals(1, reset_count)
		end)

		it("does not fire notification when previous changes track (different identity)", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			local source = make_source("mpris:spotify", { title = "Song A", status = "playing" })
			mock_reg.fire_updated(source)
			assert.equals(1, #notifications_fired)
			-- Identity will change: on_playback_action must not fire
			source.state.title = "Song B"
			-- last_identity is still "Song A|" but identity(source.state) is now "Song B|"
			mock_reg.fire_playback(source, "previous")
			assert.equals(1, #notifications_fired)
		end)

		it("creates new notification when previous is called and existing notification was dismissed", function()
			local mock_reg = make_mock_registry()
			local n = notification.new(mock_reg, nil)
			local source = make_source("mpris:spotify", { title = "Song A", status = "playing" })
			mock_reg.fire_updated(source)
			assert.equals(1, #notifications_fired)
			-- Simulate user dismissing the notification before previous fires.
			n:destroy_all()
			-- Same identity: no existing notif, so create_notification runs.
			mock_reg.fire_playback(source, "previous")
			assert.equals(2, #notifications_fired)
		end)

		it("does not fire for actions other than previous", function()
			local mock_reg = make_mock_registry()
			notification.new(mock_reg, nil)
			local source = make_source("mpris:spotify", { title = "Song A", status = "playing" })
			mock_reg.fire_updated(source)
			assert.equals(1, #notifications_fired)
			mock_reg.fire_playback(source, "next")
			assert.equals(1, #notifications_fired)
		end)
	end)
end)
