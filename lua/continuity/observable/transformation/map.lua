local Transformation = require("continuity.observable.transformation")
local Observable = require("continuity.observable")
local Subscribable = require("continuity.subscribable")
local Removable = require("continuity.removable")
local extend = require("continuity.util.extend")

local Wrapped = extend(Subscribable, Removable)

local Map = {}

---@generic T, S
---@param observable Observable<T>
---@param mapper fun(observed: T): S
---@return Observable<S>
function Map.new(observable, mapper)
	local self = Observable({})
	---@type table<string, string>
	local id_map = {}

	local function wrap(item)
		if not item.on_removed then
			return Wrapped(item)
		end
		return item
	end

	local function on_added(observed)
		local output = wrap(mapper(observed))
		self:add(output)
		id_map[observed.id] = output.id
	end

	local function on_updated(observed)
		local new = mapper(observed)
		local old_id = id_map[observed.id]
		if new.id == old_id then
			self:update(old_id, new.state)
		else
			self:remove(old_id)
			self:add(wrap(new))
			id_map[observed.id] = new.id
		end
	end

	local function on_removed(id)
		self:remove(id_map[id])
		id_map[id] = nil
	end

	return Transformation.new(observable, self, {
		on_added = on_added,
		on_updated = on_updated,
		on_removed = on_removed,
	})
end

return Map
