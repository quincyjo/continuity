require("spec.support.awesome_mocks")

local naughty = require("naughty")

-- Helper: force a fresh load of compat.naughty (load-time detection requires this when
-- switching between API path simulations within the same process).
local function reload_compat()
	package.loaded["continuity.compat.naughty"] = nil
	return require("continuity.compat.naughty")
end

-- ─── New API (git HEAD) ───────────────────────────────────────────────────────
-- Base mock has naughty.notification as a function → new API path is selected.

describe("compat.naughty [new API / git HEAD]", function()
	local nc
	local created = {}
	local signals_connected = {} -- name -> list of handlers

	before_each(function()
		created = {}
		signals_connected = {}

		naughty.notification = function(opts)
			local n = naughty.make_notification(opts)
			-- Track registered signal callbacks so tests can fire them manually.
			local registered = {}
			n.connect_signal = function(_self, name, cb)
				registered[name] = registered[name] or {}
				registered[name][#registered[name] + 1] = cb
			end
			n.emit_signal = function(_self, name, ...)
				for _, cb in ipairs(registered[name] or {}) do
					cb(...)
				end
			end
			created[#created + 1] = n
			return n
		end
		naughty.connect_signal = function(name, cb)
			signals_connected[name] = signals_connected[name] or {}
			signals_connected[name][#signals_connected[name] + 1] = cb
		end

		nc = reload_compat()
	end)

	after_each(function()
		naughty.notification = naughty.make_notification
		naughty.connect_signal = function(_name, _cb) end
	end)

	it("notify normalizes text to message before calling naughty.notification", function()
		nc.notify({ title = "T", text = "M" })
		assert.equals(1, #created)
		assert.equals("M", created[1].opts.message)
		assert.is_nil(created[1].opts.text)
	end)

	it("notify passes message field through unchanged", function()
		nc.notify({ message = "M" })
		assert.equals("M", created[1].opts.message)
	end)

	it("on_destroyed fires when the raw notification emits 'destroyed'", function()
		local fired = false
		local handle = nc.notify({ message = "M" }, function()
			fired = true
		end)
		handle._raw:emit_signal("destroyed")
		assert.is_true(fired)
	end)

	it("notify without on_destroyed does not error", function()
		assert.has_no.errors(function()
			nc.notify({ message = "M" })
		end)
	end)

	it("destroy calls notif:destroy with the given reason", function()
		local destroyed_with
		naughty.notification = function(opts)
			local n = naughty.make_notification(opts)
			n.connect_signal = function() end
			n.destroy = function(_self, reason)
				destroyed_with = reason
			end
			created[#created + 1] = n
			return n
		end
		nc = reload_compat()

		local handle = nc.notify({ message = "M" })
		nc.destroy(handle, nc.reason.dismissed_by_command)
		assert.equals(nc.reason.dismissed_by_command, destroyed_with)
	end)

	it("reason constants are snake_case", function()
		assert.is_not_nil(nc.reason.dismissed_by_command)
		assert.is_not_nil(nc.reason.dismissed_by_user)
		assert.is_not_nil(nc.reason.expired)
		assert.is_not_nil(nc.reason.silent)
		assert.is_not_nil(nc.reason.undefined)
	end)

	it("connect_signal delegates to naughty.connect_signal", function()
		local cb = function() end
		nc.connect_signal("added", cb)
		assert.equals(1, #(signals_connected["added"] or {}))
		assert.equals(cb, signals_connected["added"][1])
	end)

	it("reset_timeout calls reset_timeout on the raw notification", function()
		local called = false
		naughty.notification = function(opts)
			local n = naughty.make_notification(opts)
			n.connect_signal = function() end
			n.reset_timeout = function()
				called = true
			end
			created[#created + 1] = n
			return n
		end
		nc = reload_compat()

		local handle = nc.notify({ message = "M" })
		nc.reset_timeout(handle)
		assert.is_true(called)
	end)

	it("update_message sets message on the raw notification and returns the same handle", function()
		local handle = nc.notify({ message = "old" })
		local handle2 = nc.update_message(handle, "new")
		assert.equals(handle, handle2)
		assert.equals("new", handle._raw.message)
	end)
end)

-- ─── Old API (4.3) ────────────────────────────────────────────────────────────
-- Simulate 4.3 by removing naughty.notification before reloading the compat module.

describe("compat.naughty [old API / 4.3]", function()
	local nc
	local notify_calls = {} -- list of args tables passed to naughty.notify
	local destroy_calls = {} -- list of { notif, reason }

	before_each(function()
		notify_calls = {}
		destroy_calls = {}

		local function make_43_notif(args)
			return { _args = args, destroy_cb = args.destroy }
		end

		naughty.notification = nil -- key signal: old API path
		naughty.notify = function(args)
			notify_calls[#notify_calls + 1] = args
			return make_43_notif(args)
		end
		naughty.destroy = function(notif, reason)
			destroy_calls[#destroy_calls + 1] = { notif = notif, reason = reason }
			if notif.destroy_cb then
				notif.destroy_cb(reason)
			end
		end
		naughty.notificationClosedReason = {
			silent = -1,
			expired = 1,
			dismissedByUser = 2,
			dismissedByCommand = 3,
			undefined = 4,
		}

		nc = reload_compat()
	end)

	after_each(function()
		naughty.notification = naughty.make_notification
		naughty.notify = function(_opts)
			return { id = 1 }
		end
		naughty.destroy = nil
		naughty.notificationClosedReason = nil
		naughty.connect_signal = function(_name, _cb) end
	end)

	it("notify normalizes message to text before calling naughty.notify", function()
		nc.notify({ title = "T", message = "M" })
		assert.equals(1, #notify_calls)
		assert.equals("M", notify_calls[1].text)
		assert.is_nil(notify_calls[1].message)
	end)

	it("notify passes text field through unchanged when no message", function()
		nc.notify({ text = "T" })
		assert.equals("T", notify_calls[1].text)
	end)

	it("on_destroyed is injected as args.destroy into naughty.notify", function()
		local fired = false
		nc.notify({ message = "M" }, function()
			fired = true
		end)
		assert.is_function(notify_calls[1].destroy)
		notify_calls[1].destroy("some_reason")
		assert.is_true(fired)
	end)

	it("notify without on_destroyed does not set args.destroy", function()
		nc.notify({ message = "M" })
		assert.is_nil(notify_calls[1].destroy)
	end)

	it("destroy calls naughty.destroy with the mapped reason constant", function()
		local handle = nc.notify({ message = "M" })
		nc.destroy(handle, nc.reason.dismissed_by_command)
		assert.equals(1, #destroy_calls)
		assert.equals(naughty.notificationClosedReason.dismissedByCommand, destroy_calls[1].reason)
	end)

	it("reason constants are snake_case and map to 4.3 camelCase values", function()
		assert.equals(naughty.notificationClosedReason.dismissedByCommand, nc.reason.dismissed_by_command)
		assert.equals(naughty.notificationClosedReason.dismissedByUser, nc.reason.dismissed_by_user)
		assert.equals(naughty.notificationClosedReason.expired, nc.reason.expired)
		assert.equals(naughty.notificationClosedReason.silent, nc.reason.silent)
		assert.equals(naughty.notificationClosedReason.undefined, nc.reason.undefined)
	end)

	it("connect_signal is a no-op and does not call naughty.connect_signal", function()
		local called = false
		naughty.connect_signal = function(_name, _cb)
			called = true
		end
		nc.connect_signal("added", function() end)
		assert.is_false(called)
	end)

	it("update_message destroys the old notification and returns a new handle", function()
		local handle = nc.notify({ title = "Alt-Tab", message = "old", timeout = 0 })
		local handle2 = nc.update_message(handle, "new")
		assert.equals(1, #destroy_calls)
		assert.equals(2, #notify_calls)
		assert.equals("new", notify_calls[2].text)
		assert.not_equals(handle, handle2)
	end)

	it("update_message preserves original args (title, timeout) in the new notification", function()
		local handle = nc.notify({ title = "Alt-Tab", message = "old", timeout = 0 })
		nc.update_message(handle, "new")
		assert.equals("Alt-Tab", notify_calls[2].title)
		assert.equals(0, notify_calls[2].timeout)
	end)

	it("reset_timeout calls naughty.reset_timeout with the raw notification", function()
		local reset_called_with
		naughty.reset_timeout = function(notif)
			reset_called_with = notif
		end

		local handle = nc.notify({ message = "M" })
		nc.reset_timeout(handle)
		assert.equals(handle._raw, reset_called_with)
	end)
end)
