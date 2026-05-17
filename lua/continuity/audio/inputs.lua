---@class SinkInputState
---@field level  AudioLevel
---@field muted  AudioMuted
---@field name   string?
---@field sink   integer?
---@field corked boolean

---@class SinkInputMeta
---@field app_name  string?
---@field icon_name string?
---@field app_icon  string?
---@field role      string?
---@field binary    string?

---@class SinkInputHandle : Subscribable<SinkInputState>, Controllable<SinkInputState>, Removable
---@field id          string
---@field app_name    string?
---@field icon_name   string?
---@field app_icon    string?
---@field role        string?
---@field binary      string?
---@field state       SinkInputState
---@field move_to     fun(self: SinkInputHandle, target: SinkHandle|integer|string)

---@class InputHandles
---@field add    fun(id: string, state: SinkInputState, meta: SinkInputMeta?)
---@field update fun(id: string, state: SinkInputState)
---@field remove fun(id: string)

---@class InputCollection : Observable<SinkInputHandle>

local Observable = require("continuity.observable")
local Subscribable = require("continuity.subscribable")
local Controllable = require("continuity.controllable")
local Removable = require("continuity.removable")
local extend = require("continuity.util.extend")

local inputs = {}

---@return InputCollection, fun(api_sub: SinkInputApi): InputHandles
function inputs.new()
	local SinkInputHandle = extend(Subscribable, Controllable, Removable)
	local HandleMT = SinkInputHandle.MT

	HandleMT.__index.adjust_perc = function() end
	HandleMT.__index.set_perc = function() end
	HandleMT.__index.toggle_mute = function() end
	HandleMT.__index.move_to = function() end

	---@type ObservableInternal<SinkInputHandle, SinkInputState>
	local observable = Observable()

	local handles = {}

	function handles.add(id, initial_state, meta)
		local handle = setmetatable(
			SinkInputHandle.init({
				id = id,
				app_name = meta and meta.app_name,
				icon_name = meta and meta.icon_name,
				app_icon = meta and meta.app_icon,
				role = meta and meta.role,
				binary = meta and meta.binary,
				state = initial_state or { level = 0, muted = false },
			}),
			HandleMT
		)
		observable:add(handle)
	end

	function handles.update(id, partial_state)
		local handle = observable:get(id)
		if not handle then
			return
		end
		local changed = false
		for k, v in pairs(partial_state) do
			if v ~= nil and handle.state[k] ~= v then
				handle.state[k] = v
				changed = true
			end
		end
		if changed then
			observable:update(id, handle.state)
		end
	end

	function handles.remove(id)
		observable:remove(id)
	end

	local function bind(api_sub)
		local function update_level_muted(handle, level, muted)
			local changed = handle.state.level ~= level or handle.state.muted ~= muted
			handle.state.level = level
			handle.state.muted = muted
			if changed then
				observable:update(handle.id, handle.state)
			end
			---@cast handle SinkInputHandle|ControllableInternal<SinkInputState>
			handle:control_event(handle.state)
		end

		HandleMT.__index.adjust_perc = function(self, delta)
			---@cast self SinkInputHandle|ControllableInternal<SinkInputState>
			if delta > 0 and delta + self.state.level > 100 then
				delta = 100 - self.state.level
			elseif delta < 0 and delta + self.state.level < 0 then
				delta = -self.state.level
			end
			if delta == 0 then
				self:control_event(self.state)
				return
			end
			api_sub.adjust_perc(self.id, delta, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.set_perc = function(self, value)
			value = math.max(0, math.min(100, math.floor(value + 0.5)))
			api_sub.set_perc(self.id, value, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.toggle_mute = function(self)
			api_sub.toggle(self.id, function(level, muted)
				update_level_muted(self, level, muted)
			end)
		end

		HandleMT.__index.move_to = function(self, target)
			local sink_id = type(target) == "table" and target.id or target
			api_sub.move(self.id, sink_id, function()
				---@cast self SinkInputHandle|ControllableInternal<SinkInputState>
				self:control_event(self.state)
			end)
		end

		return handles
	end

	return observable, bind
end

return inputs
