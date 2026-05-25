local Transformation = require("continuity.observable.transformation")
local Observable = require("continuity.observable")
local Unique = {}

local function fire(cbs, ...)
	for _, cb in ipairs(cbs) do
		cb(...)
	end
end

---@generic T, K
---@param observable Observable<T>
---@param unique_by fun(observed: T): K
---@param strategy? UniqueStrategy
---@return Observable<Group<T>>
function Unique.new(observable, unique_by, strategy)
	strategy = strategy or Observable.UniqueStrategy.First
	local groups = {}
	local key_for = {}

	local self = Observable({
		all = function(_)
			local result = {}
			if strategy == Observable.UniqueStrategy.First then
				for _, group in pairs(groups) do
					result[#result + 1] = group[1]
				end
			else
				for _, group in pairs(groups) do
					result[#result + 1] = group[#group]
				end
			end
			return result
		end,
		get = function(_, id)
			local group = groups[key_for[id]]
			if group then
				if strategy == Observable.UniqueStrategy.First then
					return group[1]
				else
					return group[#group]
				end
			end
		end,
	})

	---@param id string
	---@param key `K`
	local function remove_from_group(id, key)
		key_for[id] = nil
		local group = groups[key]
		if group then
			for i, entry in ipairs(group) do
				if entry.id == id then
					if
						i == #group
						and #group > 1
						and (strategy == Observable.UniqueStrategy.Last or strategy == Observable.UniqueStrategy.Recent)
					then
						fire(self.on_updated_cbs, group[#group - 1])
					elseif i == 1 and #group > 1 and strategy == Observable.UniqueStrategy.First then
						fire(self.on_updated_cbs, group[2])
					elseif #group == 1 then
						fire(self.on_removed_cbs, key)
					end
					table.remove(group, i)
					break
				end
			end
		end
	end

	local function add_to_group(observed, key)
		local group = groups[key] or {}
		if not groups[key] then
			groups[key] = group
		end
		group[#group + 1] = observed
		if
			#group > 1
			and (strategy == Observable.UniqueStrategy.Last or strategy == Observable.UniqueStrategy.Recent)
		then
			fire(self.on_updated_cbs, group[#group])
		elseif #group == 1 then
			fire(self.on_added_cbs, observed)
		end
	end

	local function on_added(observed)
		local key = unique_by(observed)
		key_for[observed.id] = key
		add_to_group(observed, key)
	end

	local function on_updated(observed)
		local new_key = unique_by(observed)
		local old_key = key_for[observed.id]
		if new_key ~= old_key then
			remove_from_group(observed.id, old_key)
			add_to_group(observed, new_key)
		else
			local group = groups[new_key]
			if strategy == Observable.UniqueStrategy.Recent then
				if group then
					for i, entry in ipairs(group or {}) do
						if entry == observed then
							table.remove(group, i)
							break
						end
					end
					group[#group + 1] = observed
					fire(self.on_updated_cbs, observed)
				end
			elseif strategy == Observable.UniqueStrategy.Last and observed.id == group[#group].id then
				fire(self.on_updated_cbs, observed)
			else
				if strategy == Observable.UniqueStrategy.First and observed.id == group[1].id then
					fire(self.on_updated_cbs, observed)
				end
			end
		end
	end

	local function on_removed(id)
		local key = key_for[id]
		remove_from_group(id, key)
	end

	return Transformation.new(observable, self, {
		on_added = on_added,
		on_updated = on_updated,
		on_removed = on_removed,
	})
end

return Unique
