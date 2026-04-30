-- Naughty notification integration.
-- Subscribes to source lifecycle and fires per-source track-change notifications.

local naughty = require("naughty")
local awful = require("awful")
local art = require("continuity.media.art")
local PlaybackAction = require("continuity.media.registry").PlaybackAction

local notification = {}

---@alias MediaNotifyCallback fun(source: MediaSource, icon: string|nil):
---                           NaughtyNotificationArgs|nil, MediaNotificationOptions|nil

---@class MediaNotificationOptions
---@field reuse?      fun(source: MediaSource, icon: string|nil)|boolean If
---                   a function, this will be called instead of notify_callback
---                   when a new notification event occurs if the notification
---                   from the last notify_callback is not yet destroyed. If
---                   true, the notification will be kept and should be
---                   maintained internally. If nil or false, a new notification
---                   will be created on each notification event via
---                   notify_callback.
---@field on_destroy? fun(): boolean Cleanup callback called when the
---                   notification is destroyed.
---@field callback?   fun(notification: NaughtyNotification) Callback called when the
---                   notification is created.

---@class NaughtyNotificationArgs
---@field title?           string
---@field message?         string
---@field text?            string  -- alias for message; accepted by older naughty.notify() API
---@field icon?            string
---@field timeout?         number
---@field widget_template? AwesomeWidgetTemplate
---@field app_name?        string
---@field screen?          AwesomeScreen

---@alias NotificationInterceptionMode boolean|"strict"

---@class MediaNotificationOpts
---@field notify_callback?              MediaNotifyCallback Custom notification callback implementation.
---@field suppress_when_client_active?  boolean|fun(): AwesomeClient[]
--  nil/true  -> suppress when source app is visible on the focused screen (default)
--  false     -> never suppress based on focus
--  function  -> called to get the list of clients to check; suppress if any match source.app_name
---@field intercept_dbus_notifications? NotificationInterceptionMode

local default = {
	notify_callback = function(source, icon)
		return {
			title = source.state.title or "Unknown",
			message = source.state.artist or "Unknown",
			icon = icon,
			timeout = 6,
		}
	end,
	suppress_when_client_active = true,
	intercept_dbus_notifications = true,
}

--- Build the client getter function from suppress_when_client_active option.
--- Returns a function -> AwesomeClient[] for use in focus checks, or nil if disabled.
---@param opt? boolean|fun():AwesomeClient[]
---@return (fun(): AwesomeClient[])|nil
local function build_client_getter(opt)
	if opt == false then
		return nil
	elseif type(opt) == "function" then
		return opt
	else
		-- nil or true -> default: clients visible on the focused screen
		return function()
			local s = awful.screen.focused()
			if not s then
				return {}
			end
			local visible = {}
			for _, c in ipairs(s.clients) do
				if c:isvisible() then
					visible[#visible + 1] = c
				end
			end
			return visible
		end
	end
end

--- Create a notification handler.
---@param registry Registry
---@param setup_opts MediaNotificationOpts|nil
---@return table
function notification.new(registry, setup_opts)
	local notify_callback = setup_opts and setup_opts.notify_callback or default.notify_callback
	local get_clients = build_client_getter(setup_opts and setup_opts.suppress_when_client_active)
	local intercept_notifications = setup_opts and setup_opts.intercept_dbus_notifications
		or default.intercept_dbus_notifications
	local enabled = true

	---@type table<string, string>
	local last_identity = {} -- source_id -> identity string
	---@type table<string, 0|1>
	local last_status = {} -- source_id -> 0 (paused) or 1 (playing)
	---@type table<string, { notif: NaughtyNotification, opts: MediaNotificationOptions }>
	local last_notif = {} -- source_id -> naughty notification object
	---@type table<string, string>
	local current_title = {} -- source_id -> current playing title (set immediately on update)
	local last_notified_title = {} -- source_id -> title for which we last fired a notification
	local pending_dbus = {} -- title -> D-Bus notification parked pending MPRIS confirmation

	-- source_id -> MediaSource reference (kept current; dbus_senders populated async by backend)
	---@type table<string, MediaSource>
	local tracked_sources = {}

	if intercept_notifications then
		-- Suppress D-Bus notifications that duplicate a media notification we already
		-- fired (or are about to fire).  The "added" signal fires after registration
		-- but before request::display; setting ignore=true then destroying the
		-- notification here prevents it from ever being displayed.
		-- D-Bus-originated notifications carry freedesktop_hints; our own
		-- naughty.notification() calls do not, so that field is the discriminator.
		--
		-- Suppression checks in priority order:
		--   1. _unique_sender matches source.dbus_senders — reliable identity even
		--      when app_name is unavailable (e.g. Spotify Portal notifications).
		--   2. args.app_name matches source.app_name (case-insensitive) — fallback
		--      for players that do forward app_name in notifications.
		--   3. Title match against current_title / last_notified_title — legacy
		--      fallback for the MPRIS-first / D-Bus-second race; also parks
		--      unmatched notifications for update_title() to clear later.
		naughty.connect_signal("added", function(notif, args)
			if not args or not args.freedesktop_hints then
				return
			end

			local sender = args._unique_sender
			local app = args.app_name

			local matched_source
			for _, source in pairs(tracked_sources) do
				if sender and source.dbus_senders and source.dbus_senders[sender] then
					matched_source = source
					break
				elseif app and source.app_name and app:lower() == source.app_name:lower() then
					matched_source = source
					break
				end
			end

			if not args.title then
				return
			end
			-- If we have a matched source, limit suppression to only that source.
			-- Otherwise, we check all. This is required for GTK portal notifications,
			-- which have nondeterministic D-Bus sender IDs and now app-name forwarding.
			local sources_to_check = matched_source and { [matched_source.id] = matched_source }
				or intercept_notifications ~= "strict" and tracked_sources
				or nil
			if not sources_to_check then
				return
			end
			for source_id, _ in pairs(sources_to_check) do
				if args.title == current_title[source_id] or args.title == last_notified_title[source_id] then
					notif.ignore = true
					notif:destroy(naughty.notification_closed_reason.dismissed_by_command)
					return
				end
			end
			-- Only park if there are known sources (avoid accumulating unrelated notifications).
			if next(sources_to_check) then
				pending_dbus[args.title] = notif
				-- Auto-remove on expiry so update_title() doesn't find a dead reference.
				notif:connect_signal("destroyed", function()
					if pending_dbus[args.title] == notif then
						pending_dbus[args.title] = nil
					end
				end)
			end
		end)
	end

	-- TODO: Make playback boundary first class.
	local function identity(state)
		return (state.title or "") .. "|" .. (state.artist or "")
	end

	--- Returns true if the source's app is currently visible on the active screen.
	---@param source MediaSource
	---@return boolean
	local function client_is_active(source)
		if not get_clients or not source.app_name then
			return false
		end
		local app = source.app_name:lower()
		for _, c in ipairs(get_clients()) do
			if
				c.class and c.class:lower() == app:lower()
				or source.state.title and c.name and c.name:find(source.state.title, 1, true)
			then
				return true
			end
		end
		return false
	end

	--- Refresh an existing notification for the given source. If the has reuse
	--- in its options, that is always called, but the timeout is only reset if
	--- notifications are enabled.
	---@param source MediaSource The source to refresh the notification for.
	---@param existing_notif NaughtyNotification The notification to refresh.
	---@param notification_opts MediaNotificationOptions The options for the notification.
	local function refresh_notification(source, existing_notif, notification_opts)
		if enabled then -- Only reset if notifications enabled.
			existing_notif:reset_timeout()
		end
		-- Always refresh if requested so that it doesn't go stale.
		if notification_opts.reuse then
			if type(notification_opts.reuse) == "function" then
				art.resolve(source.state.art_uri, function(art_path)
					-- Refresh reuse in case `existing_notif` has timed out.
					local refreshed_reuse = last_notif[source.id] and last_notif[source.id].opts.reuse or false
					if type(refreshed_reuse) == "function" then
						refreshed_reuse(source, art_path)
					end
				end)
			end
		end
	end

	--- Create a new notification for the given source, replacing any existing
	--- notification for the source.
	---@param source MediaSource The source to refresh the notification for.
	---@param existing_notif? NaughtyNotification The notification to refresh.
	local function create_notification(source, existing_notif)
		local captured_identity = identity(source.state)
		art.resolve(source.state.art_uri, function(art_path)
			-- If the identity has changed again, another creation is in progress.
			-- This guards against a previous art resolve completing after a newer one.
			if last_identity[source.id] ~= captured_identity then
				return
			end

			-- Dismiss the previous notification for this source to avoid stacking.
			-- naughty.notification() does not automatically close the old notification,
			-- so we destroy it explicitly before creating the new one.
			-- TODO: Maybe support replaces_id for 4.X?
			if existing_notif then
				existing_notif:destroy(naughty.notification_closed_reason.dismissed_by_command)
			end

			-- Suppress if source's app is visible on the focused screen.
			if client_is_active(source) then
				return
			end

			local args, opts = notify_callback(source, art_path)
			if not args then
				return
			end
			local notif
			-- AwesomeWM master forward compatibility.
			if type(naughty.notification) == "function" then
				-- New API
				args.message = args.message or args.text
				notif = naughty.notification(args)
			else
				-- 4.3 and older API
				args.text = args.text or args.message
				notif = naughty.notify(args)
			end

			last_notif[source.id] = {
				notif = notif,
				opts = opts or {},
			}
			last_notified_title[source.id] = source.state.title

			if opts and opts.callback then
				opts.callback(notif)
			end

			notif:connect_signal("destroyed", function()
				if opts and opts.on_destroy then
					opts.on_destroy()
				end
				last_notif[source.id] = nil
			end)
		end)
	end

	---@param source MediaSource
	local function intercept_dbus(source)
		local title = source.state.title
		current_title[source.id] = title
		if title then
			local pending = pending_dbus[title]
			if pending then
				pending_dbus[title] = nil
				pending:destroy(naughty.notification_closed_reason.dismissed_by_command)
			end
		end
	end

	local n = {}

	--- Enable notifications.
	function n:enable()
		enabled = true
	end

	--- Disable notifications.
	function n:disable()
		enabled = false
	end

	--- Destroy all notifications.
	function n:destroy_all()
		for id, last in pairs(last_notif) do
			last.notif:destroy(naughty.notification_closed_reason.dismissed_by_command)
			last_notif[id] = nil
		end
	end

	local function notify(source)
		local status = source.state.status == "playing" and 1 or 0
		local id = identity(source.state)
		local last = last_notif[source.id]
		local last_id = last_identity[source.id]
		last_identity[source.id] = id
		last_status[source.id] = status
		if last and last.notif and (id == last_id or last.opts.reuse) then
			refresh_notification(source, last.notif, last.opts)
		elseif enabled then
			create_notification(source, last and last.notif)
		end
	end

	---@param source MediaSource
	function n.on_source_updated(source)
		-- Update current_title and clear any parked D-Bus notification for this
		-- title before we fire our own notification below.
		if intercept_notifications then
			intercept_dbus(source)
		end

		tracked_sources[source.id] = source

		local status = source.state.status == "playing" and 1 or 0
		local id = identity(source.state)

		-- Delay notification of new sources until they start playing.
		if (source.state.status ~= "playing" or not source.state.title) and last_status[source.id] == nil then
			return
		end

		-- Nothing to notify.
		if id == last_identity[source.id] and status == last_status[source.id] then
			return
		end

		notify(source)
	end

	---@param source_id string
	function n.on_source_removed(source_id)
		-- Clear any parked D-Bus notification for this source's last known title.
		local title = current_title[source_id]
		if title then
			pending_dbus[title] = nil
		end
		if last_notif[source_id] then
			last_notif[source_id].notif:destroy(naughty.notification_closed_reason.dismissed_by_command)
		end
		current_title[source_id] = nil
		last_notified_title[source_id] = nil
		last_identity[source_id] = nil
		tracked_sources[source_id] = nil
		last_notif[source_id] = nil
		last_status[source_id] = nil
	end

	---@param source MediaSource
	---@param action PlaybackAction
	-- last_identity is nil until the source has fired at least one notifiable update;
	-- when nil the identity comparison fails and this is a correct no-op.
	function n.on_playback_action(source, action)
		if action == PlaybackAction.Previous and identity(source.state) == last_identity[source.id] then
			notify(source)
		end
	end

	registry.on_source_added(n.on_source_updated)
	registry.on_source_updated(n.on_source_updated)
	registry.on_source_removed(n.on_source_removed)
	registry.on_playback_action(n.on_playback_action)

	return n
end

return notification
