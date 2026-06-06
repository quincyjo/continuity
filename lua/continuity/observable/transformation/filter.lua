local Transformation = require("continuity.observable.transformation")
local Observable = require("continuity.observable")

local Filter = {}

---@generic T
---@param observable Observable<T>
---@param predicate fun(observed: T): boolean
---@return Observable<T>
function Filter.new(observable, predicate)
	local self = Observable({})

	local function on_added(observed)
		if predicate(observed) then
			self:add(observed)
		end
	end

	local function on_updated(observed)
		local was_passing = self.items[observed.id] ~= nil
		local is_passing = predicate(observed)
		if was_passing and is_passing then
			self._on_updated_cbs:fire(observed)
		elseif was_passing and not is_passing then
			self.items[observed.id] = nil
			self._on_removed_cbs:fire(observed.id)
		elseif not was_passing and is_passing then
			self:add(observed)
		end
	end

	local function on_removed(id)
		if self.items[id] then
			self.items[id] = nil
			self._on_removed_cbs:fire(id)
		end
	end

	return Transformation.new(observable, self, {
		on_added = on_added,
		on_updated = on_updated,
		on_removed = on_removed,
	})
end

return Filter
