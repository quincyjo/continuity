local Transformation = require("continuity.observable.transformation")
local Observable = require("continuity.observable")
local Subscribable = require("continuity.class.subscribable")
local Removable = require("continuity.class.removable")
local class = require("continuity.class")

local Wrapped = class.union(Subscribable, Removable)

local Flatmap = {}

---@generic T, S
---@param observable Observable<T>
---@param mapper fun(observed: T): S[]
---@return Observable<S>
function Flatmap.new(observable, mapper)
	local self = Observable({})
	---@type table<string, string[]>
	local ids_map = {}

	local function wrap(item)
		if not item.on_removed then
			return Wrapped(item)
		end
		return item
	end

	local function on_added(observed)
		local outputs = mapper(observed)
		local ids = {}
		for _, output in ipairs(outputs) do
			output = wrap(output)
			self:add(output)
			ids[output.id] = true
		end
		ids_map[observed.id] = ids
	end

	local function on_updated(observed)
		local new_outputs = mapper(observed)
		local old_ids = ids_map[observed.id] or {}

		local new_by_id = {}
		for _, output in ipairs(new_outputs) do
			new_by_id[output.id] = output
		end

		local new_ids = {}
		for _, output in ipairs(new_outputs) do
			new_ids[output.id] = true
			if old_ids[output.id] then
				self:update(output.id, output.state)
			else
				self:add(wrap(output))
			end
		end

		for id in pairs(old_ids) do
			if not new_by_id[id] then
				self:remove(id)
			end
		end

		ids_map[observed.id] = new_ids
	end

	local function on_removed(id)
		for output_id in pairs(ids_map[id] or {}) do
			self:remove(output_id)
		end
		ids_map[id] = nil
	end

	return Transformation.new(observable, self, {
		on_added = on_added,
		on_updated = on_updated,
		on_removed = on_removed,
	})
end

return Flatmap
