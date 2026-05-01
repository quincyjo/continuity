local gears = require("gears")

---@alias BacklightKind "display"|"keyboard"

---@class BacklightState
---@field id         string
---@field kind       BacklightKind
---@field brightness number

---@class BacklightUpdate
---@field brightness number
---@field raw        integer|nil

---@class BacklightHandle
---@field id          string|nil
---@field kind        BacklightKind
---@field brightness  number
---@field steps       integer|nil
---@field raw         integer|nil
---@field on_ready    fun(self: BacklightHandle, fn: fun(update: BacklightUpdate))
---@field on_control  fun(self: BacklightHandle, fn: fun(update: BacklightUpdate)): fun()
---@field subscribe   fun(self: BacklightHandle, fn: fun(update: BacklightUpdate)): fun()
---@field unsubscribe fun(self: BacklightHandle, fn: fun(update: BacklightUpdate))
---@field set_perc    fun(self: BacklightHandle, value: number)
---@field adjust_perc fun(self: BacklightHandle, delta: integer)
---@field set         fun(self: BacklightHandle, step: integer)
---@field adjust      fun(self: BacklightHandle, delta: integer)

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

local _backend = nil ---@type BacklightBackend|nil
local _setup_called = false
local _handles = {} ---@type table<string, BacklightHandle>
local _device_added_subs = {}
local _device_removed_subs = {}

local function _on_control(handle, brightness, raw)
	local changed = handle.brightness ~= brightness
	handle.brightness = brightness
	handle.raw = raw
	local update = { brightness = brightness, raw = raw }
	if changed then
		---@diagnostic disable-next-line: undefined-field
		for _, sub in ipairs(handle._private.subscribers) do
			sub(update)
		end
	end
	---@diagnostic disable-next-line: undefined-field
	for _, cb in ipairs(handle._private.on_control_cbs) do
		cb(update)
	end
end

local HandleMeta = {
	__index = {
		on_ready = function(self, fn)
			if self._private.initialized then
				fn({ brightness = self.brightness, raw = self.raw })
			else
				self._private.on_ready_cbs[#self._private.on_ready_cbs + 1] = fn
			end
		end,

		on_control = function(self, fn)
			self._private.on_control_cbs[#self._private.on_control_cbs + 1] = fn
			return function()
				for i, sub in ipairs(self._private.on_control_cbs) do
					if sub == fn then
						table.remove(self._private.on_control_cbs, i)
						return
					end
				end
			end
		end,

		subscribe = function(self, fn)
			self._private.subscribers[#self._private.subscribers + 1] = fn
			return function()
				self:unsubscribe(fn)
			end
		end,

		unsubscribe = function(self, fn)
			for i, sub in ipairs(self._private.subscribers) do
				if sub == fn then
					table.remove(self._private.subscribers, i)
					return
				end
			end
		end,

		set_perc = function(self, value)
			if not self.id or not _backend then
				return
			end
			_backend:set_perc(self.id, math.max(0, math.min(100, value)), function(brightness, raw)
				_on_control(self, brightness, raw)
			end)
		end,

		adjust_perc = function(self, delta)
			if not self.id or not _backend then
				return
			end
			_backend:adjust_perc(self.id, delta, function(brightness, raw)
				_on_control(self, brightness, raw)
			end)
		end,

		set = function(self, step)
			if not self.id or not _backend or not _backend.set then
				return
			end
			_backend:set(self.id, step, function(brightness, raw)
				_on_control(self, brightness, raw)
			end)
		end,

		adjust = function(self, delta)
			if not self.id or not _backend or not _backend.adjust then
				return
			end
			_backend:adjust(self.id, delta, function(brightness, raw)
				_on_control(self, brightness, raw)
			end)
		end,
	},
}

---@return BacklightHandle
local function make_handle(kind)
	local handle = {
		id = nil,
		kind = kind,
		brightness = 0,
		steps = nil,
		_private = {
			initialized = false,
			on_ready_cbs = {},
			on_control_cbs = {},
			subscribers = {},
		},
	}
	setmetatable(handle, HandleMeta)
	return handle
end

local backlight = {}

---@type BacklightHandle
backlight.primary_display = make_handle("display")
backlight.displays = {}

---@param info BacklightDeviceInfo
local function _on_device_added(info)
	local handle
	if info.kind == "display" and not backlight.primary_display.id then
		handle = backlight.primary_display
	else
		handle = make_handle(info.kind)
	end
	---@diagnostic disable-next-line: undefined-field
	local private = handle._private
	handle.id = info.id
	handle.brightness = info.brightness
	handle.steps = info.steps
	handle.raw = info.raw
	private.initialized = true
	local ready_update = { brightness = info.brightness, raw = info.raw }
	for _, cb in ipairs(private.on_ready_cbs) do
		cb(ready_update)
	end
	private.on_ready_cbs = nil
	_handles[info.id] = handle
	if info.kind == "display" then
		backlight.displays[#backlight.displays + 1] = handle
	end
	for _, sub in ipairs(_device_added_subs) do
		sub(handle)
	end
end

local function _on_device_removed(id)
	local handle = _handles[id]
	_handles[id] = nil
	if handle then
		for i, h in ipairs(backlight.displays) do
			if h == handle then
				table.remove(backlight.displays, i)
				break
			end
		end
	end
	for _, sub in ipairs(_device_removed_subs) do
		sub(id)
	end
end

local function _on_change(id, brightness, raw)
	local handle = _handles[id]
	if handle then
		if handle.brightness == brightness then
			return
		end
		handle.brightness = brightness
		handle.raw = raw
		local update = { brightness = brightness, raw = raw }
		---@diagnostic disable-next-line: undefined-field
		for _, sub in ipairs(handle._private.subscribers) do
			sub(update)
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

---@return BacklightHandle[]
function backlight.all()
	local result = {}
	for _, handle in pairs(_handles) do
		result[#result + 1] = handle
	end
	return result
end

---@param fn fun(handle: BacklightHandle)
---@return fun()
function backlight.on_device_added(fn)
	_device_added_subs[#_device_added_subs + 1] = fn
	return function()
		for i, sub in ipairs(_device_added_subs) do
			if sub == fn then
				table.remove(_device_added_subs, i)
				return
			end
		end
	end
end

---@param fn fun(id: string)
---@return fun()
function backlight.on_device_removed(fn)
	_device_removed_subs[#_device_removed_subs + 1] = fn
	return function()
		for i, sub in ipairs(_device_removed_subs) do
			if sub == fn then
				table.remove(_device_removed_subs, i)
				return
			end
		end
	end
end

function backlight.stop()
	if _backend then
		_backend:stop()
		_backend = nil
	end
	_handles = {}
	_device_added_subs = {}
	_device_removed_subs = {}
	_setup_called = false
	backlight.primary_display = make_handle("display")
	backlight.displays = {}
end

return backlight
