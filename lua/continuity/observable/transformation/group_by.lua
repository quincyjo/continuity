---@class Group<K, T> : Subscribable<T[]>, Removable
---@field id K
---@field state T[]

local Transformation = require("continuity.observable.transformation")
local Observable = require("continuity.observable")
local Subscribable = require("continuity.class.subscribable")
local Removable = require("continuity.class.removable")
local class = require("continuity.class")

local Group = class.union("Group", Subscribable, Removable)

local GroupBy = {}

---@generic T, K
---@param observable Observable<T>
---@param group_by fun(observed: T): K
---@return Observable<Group<K, T>>
function GroupBy.new(observable, group_by)
	---@type ObservableInternal<Group<`K`, `T`>, `T`[]>
	local self = Observable({})
	---@type table<string, `K`>
	local group_for = {}

	---@param id string
	---@param key `K`
	local function remove_from_group(id, key)
		group_for[id] = nil
		local group = self.items[key]
		if group then
			for i, entry in ipairs(group.state) do
				if entry.id == id then
					table.remove(group.state, i)
					break
				end
			end
			if #group.state == 0 then
				self:remove(key)
			else
				self:update(key, group.state)
			end
		end
	end

	local function add_to_group(observed, key)
		group_for[observed.id] = key
		local group = self.items[key]
		if not group then
			self:add(Group({ id = key, state = { observed } }))
		else
			table.insert(group.state, observed)
			self:update(key, group.state)
		end
	end

	local function on_added(observed)
		local key = group_by(observed)
		add_to_group(observed, key)
	end

	local function on_updated(observed)
		local new_key = group_by(observed)
		local old_key = group_for[observed.id]
		if new_key ~= old_key then
			remove_from_group(observed.id, old_key)
			add_to_group(observed, new_key)
		end
	end

	local function on_removed(id)
		local key = group_for[id]
		remove_from_group(id, key)
	end

	return Transformation.new(observable, self, {
		on_added = on_added,
		on_updated = on_updated,
		on_removed = on_removed,
	})
end

return GroupBy
