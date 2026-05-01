-- Normalized naughty API across Awesome 4.3 and git HEAD.
-- Detection is performed once at load time; no per-call branching in callers.
--
-- Usage:
--   local nc = require("compat.naughty")
--   local handle = nc.notify({ title = "T", message = "M" }, on_destroyed_cb)
--   nc.destroy(handle, nc.reason.dismissed_by_command)
--   handle = nc.update_message(handle, "new text")  -- reassign; may be a new handle on 4.3

local naughty = require("naughty")

---@class CompatNotification
---@field _raw table   The underlying naughty notification object
---@field _args table  Original notification args (retained for 4.3 destroy+recreate)

---@class NaughtyGitNotification  Raw notification object from Awesome git HEAD (naughty.notification OOP API).
---@field ignore boolean           Set true before destroy to suppress display entirely.
---@field destroy fun(self: NaughtyGitNotification, reason: any)
---@field connect_signal fun(self: NaughtyGitNotification, name: string, fn: function)

local M = {}

local is_new_api = type(naughty.notification) == "function"

if is_new_api then
	-- ── git HEAD (naughty.notification OOP API) ───────────────────────────────

	---@param args table             Notification args. `text` normalized to `message`.
	---@param on_destroyed? function Called when the notification is destroyed.
	---@return CompatNotification
	function M.notify(args, on_destroyed)
		args.message = args.message or args.text
		args.text = nil
		local notif = naughty.notification(args)
		if on_destroyed then
			notif:connect_signal("destroyed", on_destroyed)
		end
		return { _raw = notif, _args = args }
	end

	---@param handle CompatNotification
	---@param reason any  Use `M.reason.*`
	function M.destroy(handle, reason)
		handle._raw:destroy(reason)
	end

	---@param handle CompatNotification
	---@param msg string
	---@return CompatNotification  Same handle (property updated in place)
	function M.update_message(handle, msg)
		handle._raw.message = msg
		return handle
	end

	---@param handle CompatNotification
	function M.reset_timeout(handle)
		handle._raw:reset_timeout()
	end

	M.reason = naughty.notification_closed_reason

	---@param name string
	---@param fn fun(notification: NaughtyGitNotification, ...)  Callback receives the raw git HEAD notification — use its API directly.
	function M.connect_signal(name, fn)
		naughty.connect_signal(name, fn)
	end
else
	-- ── Awesome 4.3 (naughty.notify procedural API) ───────────────────────────

	local r43 = naughty.notificationClosedReason

	M.reason = {
		dismissed_by_command = r43.dismissedByCommand,
		dismissed_by_user = r43.dismissedByUser,
		expired = r43.expired,
		silent = r43.silent,
		undefined = r43.undefined,
	}

	---@param args table             Notification args. `message` normalized to `text`.
	---@param on_destroyed? function Injected as `args.destroy` (4.3 creation-time callback).
	---@return CompatNotification
	function M.notify(args, on_destroyed)
		args.text = args.text or args.message
		args.message = nil
		if on_destroyed then
			args.destroy = on_destroyed
		end
		local notif = naughty.notify(args)
		return { _raw = notif, _args = args }
	end

	---@param handle CompatNotification
	---@param reason any  Use `M.reason.*`
	function M.destroy(handle, reason)
		naughty.destroy(handle._raw, reason)
	end

	---@param handle CompatNotification
	---@param msg string
	---@return CompatNotification  New handle (4.3 has no in-place property update)
	function M.update_message(handle, msg)
		naughty.destroy(handle._raw, M.reason.silent)
		local new_args = {}
		for k, v in pairs(handle._args) do
			new_args[k] = v
		end
		new_args.text = msg
		new_args.message = nil
		local notif = naughty.notify(new_args)
		return { _raw = notif, _args = new_args }
	end

	---@param handle CompatNotification
	function M.reset_timeout(handle)
		naughty.reset_timeout(handle._raw)
	end

	---@param _name string
	---@param _fn function
	function M.connect_signal(_name, _fn)
		-- no-op: 4.3 naughty has no module-level signal infrastructure
	end
end

return M
