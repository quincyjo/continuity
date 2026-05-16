local gears = require("gears")

---@alias BacklightKind "display"|"keyboard"

---@class BacklightState
---@field brightness number
---@field raw        integer|nil

---@class BacklightUpdate
---@field brightness number
---@field raw        integer|nil

---@class BacklightHandle : ReadyAware<BacklightUpdate>, Controllable<BacklightUpdate>
---@field id          string|nil
---@field kind        BacklightKind
---@field state       BacklightState
---@field steps       integer|nil
---@field set_perc    fun(self: BacklightHandle, value: number)
---@field adjust_perc fun(self: BacklightHandle, delta: integer)
---@field set         fun(self: BacklightHandle, step: integer)
---@field adjust      fun(self: BacklightHandle, delta: integer)
---@field unsubscribe fun(self: BacklightHandle, fn: fun(update: BacklightUpdate))

---@class BacklightDeviceInfo
---@field id         string
---@field kind       BacklightKind
---@field brightness number
---@field raw?       integer
---@field steps?     integer

---@class BacklightBackendCallbacks
---@field on_device_added   fun(device: BacklightDeviceInfo)
---@field on_device_removed fun(id: string)
---@field on_change         fun(id: string, brightness: number)

---@class BacklightBackend
---@field start       fun(self, callbacks: BacklightBackendCallbacks)
---@field stop        fun(self)
---@field set_perc    fun(self, id: string, value: number, cb?: fun(brightness: number, raw: integer|nil))
---@field adjust_perc fun(self, id: string, delta: integer, cb?: fun(brightness: number, raw: integer|nil))
---@field set?        fun(self, id: string, step: integer, cb?: fun(brightness: number, raw: integer|nil))
---@field adjust?     fun(self, id: string, delta: integer, cb?: fun(brightness: number, raw: integer|nil))

---@class BacklightOpts
---@field backend? BacklightBackend

---@class BacklightDevices : Observable<BacklightHandle>

local Observable = require("continuity.observable")
local ReadyAware = require("continuity.readyaware")
local Controllable = require("continuity.controllable")
local extend = require("continuity.util.extend")

local BacklightHandle = extend(ReadyAware, Controllable)

local _backend = nil ---@type BacklightBackend|nil
local _setup_called = false
local _handles = {} ---@type table<string, BacklightHandle>
local _devices_added_subs = {}
local _devices_removed_subs = {}
local _devices_updated_subs = {}

local function _on_control(handle, brightness, raw)
	local changed = handle.state.brightness ~= brightness
	handle.state.brightness = brightness
	handle.state.raw = raw
	if changed then
		---@cast handle ReadyAwareInternal<BacklightUpdate>
		handle:push(handle.state)
		for _, cb in ipairs(_devices_updated_subs) do
			cb(handle)
		end
	end
	---@cast handle ControllableInternal<BacklightUpdate>
	handle:control_event(handle.state)
end

local HandleMeta = BacklightHandle.MT

---@deprecated Use the function returned by subscribe() instead.
HandleMeta.__index.unsubscribe = function(self, fn)
	for i, sub in ipairs(self._subs) do
		if sub == fn then
			table.remove(self._subs, i)
			return
		end
	end
end

HandleMeta.__index.set_perc = function(self, value)
	if not self.id or not _backend then
		return
	end
	_backend:set_perc(self.id, math.max(0, math.min(100, value)), function(brightness, raw)
		_on_control(self, brightness, raw)
	end)
end

HandleMeta.__index.adjust_perc = function(self, delta)
	if not self.id or not _backend then
		return
	end
	_backend:adjust_perc(self.id, delta, function(brightness, raw)
		_on_control(self, brightness, raw)
	end)
end

HandleMeta.__index.set = function(self, step)
	if not self.id or not _backend or not _backend.set then
		return
	end
	_backend:set(self.id, step, function(brightness, raw)
		_on_control(self, brightness, raw)
	end)
end

HandleMeta.__index.adjust = function(self, delta)
	if not self.id or not _backend or not _backend.adjust then
		return
	end
	_backend:adjust(self.id, delta, function(brightness, raw)
		_on_control(self, brightness, raw)
	end)
end

---@return BacklightHandle
local function make_handle(kind)
	local handle = {
		id = nil,
		kind = kind,
		state = { brightness = 0, raw = nil },
		steps = nil,
	}
	BacklightHandle.init(handle)
	return setmetatable(handle, HandleMeta)
end

local backlight = {}

---@type BacklightHandle
backlight.primary_display = make_handle("display")

---@param info BacklightDeviceInfo
local function _on_device_added(info)
	local handle
	if info.kind == "display" and not backlight.primary_display.id then
		handle = backlight.primary_display
	else
		handle = make_handle(info.kind)
	end
	handle.id = info.id
	handle.steps = info.steps
	---@cast handle ReadyAwareInternal<BacklightUpdate>
	handle:push({ brightness = info.brightness, raw = info.raw })
	_handles[info.id] = handle
	for _, sub in ipairs(_devices_added_subs) do
		sub(handle)
	end
end

local function _on_device_removed(id)
	local handle = _handles[id]
	if handle then
		BacklightHandle.init(handle)
		_handles[id] = nil
	end
	for _, sub in ipairs(_devices_removed_subs) do
		sub(id)
	end
end

local function _on_change(id, brightness, raw)
	local handle = _handles[id]
	if handle then
		if handle.state.brightness == brightness then
			return
		end
		handle.state.brightness = brightness
		handle.state.raw = raw
		---@cast handle ReadyAwareInternal<BacklightUpdate>
		handle:push(handle.state)
		for _, cb in ipairs(_devices_updated_subs) do
			cb(handle)
		end
	end
end

---@param opts BacklightOpts
function backlight.setup(opts)
	if _setup_called then
		gears.debug.print_warning("backlight: setup() called more than once; ignoring")
		return
	end
	_setup_called = true
	opts = opts or {}
	_backend = opts.backend or require("continuity.backlight.backends.sysfs")()
	_backend:start({
		on_device_added = _on_device_added,
		on_device_removed = _on_device_removed,
		on_change = _on_change,
	})
end

---@type BacklightDevices
backlight.devices = Observable({
	on_added = function(cb)
		_devices_added_subs[#_devices_added_subs + 1] = cb
		return function()
			for i, sub in ipairs(_devices_added_subs) do
				if sub == cb then
					table.remove(_devices_added_subs, i)
					return
				end
			end
		end
	end,

	on_updated = function(cb)
		_devices_updated_subs[#_devices_updated_subs + 1] = cb
		return function()
			for i, sub in ipairs(_devices_updated_subs) do
				if sub == cb then
					table.remove(_devices_updated_subs, i)
					return
				end
			end
		end
	end,

	on_removed = function(cb)
		_devices_removed_subs[#_devices_removed_subs + 1] = cb
		return function()
			for i, sub in ipairs(_devices_removed_subs) do
				if sub == cb then
					table.remove(_devices_removed_subs, i)
					return
				end
			end
		end
	end,

	all = function()
		local result = {}
		for _, handle in pairs(_handles) do
			result[#result + 1] = handle
		end
		return result
	end,

	get = function(id)
		return _handles[id]
	end,
})

function backlight.stop()
	if _backend then
		_backend:stop()
		_backend = nil
	end
	_handles = {}
	_devices_added_subs = {}
	_devices_updated_subs = {}
	_devices_removed_subs = {}
	_setup_called = false
	backlight.primary_display = make_handle("display")
end

return backlight
