-- Media backend module.
-- Public API: setup(), on_source_added(), on_source_updated(), on_source_removed(), sources()
-- Call media.setup({...}) once in rc.lua. Subscribe from anywhere via on_source_*.

local registry_mod = require("continuity.media.registry")
local notification_mod = require("continuity.media.notification")

---@class MediaSetupOpts
---@field backends?      Backend[]
---@field sources?       MediaSourceConfig[]
---@field notifications? MediaNotificationOpts|boolean

---@alias PlaybackStatus "playing"|"paused"|"stopped"
---@alias PlaybackLoop "none"|"track"|"playlist"

---@class MediaState
---@field uri?            string
---@field track_id?       string
---@field title?          string
---@field artist?         string
---@field album?          string
---@field album_artist?   string
---@field genre?          string
---@field date?           string
---@field track_number?   integer
---@field disc_number?    integer
---@field duration?       number
---@field status?         PlaybackStatus
---@field position?       number
---@field volume?         integer
---@field shuffle?        boolean
---@field loop?           PlaybackLoop
---@field consume?        boolean
---@field queue_position? integer
---@field queue_length?   integer
---@field art_uri?        string

---@alias PlaybackAction "play"|"pause"|"play_pause"|"stop"|"next"|"previous"|"seek"|"set_position"

---@class Playback             -- consumer-facing; constructed by registry; closed over source_id
---@field can_seek        boolean
---@field can_go_next     boolean
---@field can_go_previous boolean
---@field can_play        boolean
---@field can_pause       boolean
---@field play            fun(self)
---@field pause           fun(self)
---@field play_pause      fun(self)
---@field stop            fun(self)
---@field next            fun(self)
---@field previous        fun(self)
---@field seek            fun(self, offset_seconds: number)
---@field set_position    fun(self, pos_seconds: number)

---@class Position             -- consumer-facing; constructed by registry; closed over source_id
---@field subscribe fun(self, cb: fun(pos: number)): fun()
---@field get       fun(self, cb: fun(pos: number|nil))

---@class MediaSource
---@field id            string
---@field name          string
---@field app_name?     string               -- application identity (e.g. "spotify"); used for notification suppression
---@field app_icon?     string               -- resolved icon path from DesktopEntry (e.g. "/usr/share/icons/…/spotify.png")
---@field dbus_senders? table<string, true>  -- D-Bus unique bus names for this source (e.g. {[":1.35"]=true})
---@field state         MediaState
---@field position?     Position
---@field playback?     Playback
---@field subscribe     fun(self, cb: fun(state: MediaState), opts: RegistrySubscribeOpts?): fun()
---@field on_removed    fun(self, cb: fun(source_id: string)): fun()
---@field active        fun(self: MediaSource): boolean

local Observable = require("continuity.observable")

local _registry = nil
local _notifications = nil

---@class continuity.media
local media = {}

media.PlaybackAction = registry_mod.PlaybackAction

--- Initialize the media module.
---@param opts MediaSetupOpts
function media.setup(opts)
	assert(not _registry, "media.setup() called more than once")
	opts = opts or {}

	_registry = registry_mod.new()

	local notification_opts = opts.notifications
	if notification_opts ~= false then
		_notifications =
			notification_mod.new(_registry, type(notification_opts) == "table" and notification_opts or nil)
	end

	local registrar
	if opts.sources and #opts.sources > 0 then
		local coalescer_mod = require("continuity.media.coalescer")
		registrar = coalescer_mod.new(opts.sources).make_registrar(_registry.registrar())
	else
		registrar = _registry.registrar()
	end

	for _, backend in ipairs(opts.backends or { require("continuity.media.backends.mpris")({}) }) do
		backend:start(registrar)
	end
end

---@class MediaSources : Observable<MediaSource>
---@field on_updated fun(cb: fun(source: MediaSource), opts?: RegistrySubscribeOpts): fun()

--- Source lifecycle subscriptions and snapshot accessor.
--- on_updated debounce opts allow multi-backend coalescing to settle before firing.
---@type MediaSources
media.sources = Observable({
	on_added = function(_, cb)
		assert(_registry, "media.sources:on_added() called before media.setup()")
		return _registry.on_source_added(cb)
	end,

	on_updated = function(_, cb, opts)
		assert(_registry, "media.sources:on_updated() called before media.setup()")
		return _registry.on_source_updated(cb, opts)
	end,

	on_removed = function(_, cb)
		assert(_registry, "media.sources:on_removed() called before media.setup()")
		return _registry.on_source_removed(cb)
	end,

	all = function(_)
		if not _registry then
			return {}
		end
		return _registry.sources()
	end,

	get = function(_, id)
		if not _registry then
			return nil
		end
		return _registry.get(id)
	end,
})

--- Toggle playback of the most recently registered media source.
function media.play_pause()
	local sources = media.sources:all()
	for i = #sources, 1, -1 do
		local source = sources[i]
		if source:active() and source.playback then
			source.playback:play_pause()
			return
		end
	end
end

--- Stop playback of the most recently registered media source.
function media.stop()
	local sources = media.sources:all()
	for i = #sources, 1, -1 do
		local source = sources[i]
		if source:active() and source.playback then
			source.playback:stop()
			return
		end
	end
end

--- Go to the next track of the most recently registered media source.
function media.next()
	local sources = media.sources:all()
	for i = #sources, 1, -1 do
		local source = sources[i]
		if source:active() and source.playback then
			source.playback:next()
			return
		end
	end
end

--- Go to the previous track of the most recently registered media source.
function media.previous()
	local sources = media.sources:all()
	for i = #sources, 1, -1 do
		local source = sources[i]
		if source:active() and source.playback then
			source.playback:previous()
			return
		end
	end
end

--- Enable media notifications.
function media.enable_notifications()
	if _notifications then
		_notifications:enable()
	end
end

--- Disable media notifications.
function media.disable_notifications()
	if _notifications then
		_notifications:disable()
	end
end

--- Destroy all media notifications.
function media.destroy_all_notifications()
	if _notifications then
		_notifications:destroy_all()
	end
end

return media
