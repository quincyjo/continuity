---@class Observable<T>
---@field on_added   fun(cb: fun(handle: T)): fun()
---@field on_updated fun(cb: fun(handle: T)): fun()
---@field on_removed fun(cb: fun(id: string)): fun()
---@field all        fun(): T[]
---@field get        fun(id: string): T|nil
---@field group_by   fun(group_by: fun(observed: T): `K`): Observable<Group<`K`, T>>
---@field unique     fun(unique_by: fun(observed: T): `K`, strategy: nil|UniqueStrategy): Observable<T>

---@class Group<K, T>
---@field id K
---@field entries T[]

local Observable = {}

---@enum UniqueStrategy
Observable.UniqueStrategy = {
	First = "first",
	Last = "last",
	Recent = "recent",
}

Observable.MT = {
	__index = {
		---@generic K, T
		---@param observable Observable<T>
		---@param group_by fun(observed: T): K
		---@return Observable<Group<K, T>>
		group_by = function(observable, group_by)
			local groups = {}
			local group_for = {}

			local on_added_cbs = {}
			local on_updated_cbs = {}
			local on_removed_cbs = {}

			local function fire(cbs, ...)
				for _, cb in ipairs(cbs) do
					cb(...)
				end
			end

			local function make_unsub(cbs, cb)
				return function()
					for i = #cbs, 1, -1 do
						if cbs[i] == cb then
							table.remove(cbs, i)
						end
					end
				end
			end

			---@param id string
			---@param key `K`
			local function remove_from_group(id, key)
				group_for[id] = nil
				local group = groups[key]
				if group then
					for i, entry in ipairs(group) do
						if entry.id == id then
							table.remove(group, i)
							break
						end
					end
					if #group == 0 then
						groups[key] = nil
						fire(on_removed_cbs, key)
					else
						fire(on_updated_cbs, { id = key, entries = group })
					end
				end
			end

			local function on_added(observed)
				local key = group_by(observed)
				group_for[observed.id] = key
				local group = groups[key]
				if not group then
					group = {}
					groups[key] = group
				end
				table.insert(group, observed)
				if #group == 1 then
					fire(on_added_cbs, { id = key, entries = group })
				else
					fire(on_updated_cbs, { id = key, entries = group })
				end
			end

			local function on_updated(observed)
				local new_key = group_by(observed)
				local old_key = group_for[observed.id]
				if new_key ~= old_key then
					remove_from_group(observed.id, old_key)
					on_added(observed)
				end
			end

			local function on_removed(id)
				local key = group_for[id]
				remove_from_group(id, key)
			end

			observable.on_added(on_added)
			observable.on_updated(on_updated)
			observable.on_removed(on_removed)

			return {
				on_added = function(cb)
					table.insert(on_added_cbs, cb)
					return make_unsub(on_added_cbs, cb)
				end,
				on_updated = function(cb)
					table.insert(on_updated_cbs, cb)
					return make_unsub(on_updated_cbs, cb)
				end,
				on_removed = function(cb)
					table.insert(on_removed_cbs, cb)
					return make_unsub(on_removed_cbs, cb)
				end,
				all = function()
					local result = {}
					for key, group in pairs(groups) do
						table.insert(result, { id = key, entries = group })
					end
					return result
				end,
			}
		end,

		---@generic K, T
		---@param observable Observable<T>
		---@param unique_by fun(observed: T): K
		---@param strategy? UniqueStrategy
		---@return Observable<T>
		unique = function(observable, unique_by, strategy)
			strategy = strategy or Observable.UniqueStrategy.First
			local groups = {}
			local key_for = {}

			local on_added_cbs = {}
			local on_updated_cbs = {}
			local on_removed_cbs = {}

			local function fire(cbs, ...)
				for _, cb in ipairs(cbs) do
					cb(...)
				end
			end

			local function make_unsub(cbs, cb)
				return function()
					for i = #cbs, 1, -1 do
						if cbs[i] == cb then
							table.remove(cbs, i)
						end
					end
				end
			end

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
								and (
									strategy == Observable.UniqueStrategy.Last
									or strategy == Observable.UniqueStrategy.Recent
								)
							then
								fire(on_updated_cbs, group[#group - 1])
							elseif i == 1 and #group > 1 and strategy == Observable.UniqueStrategy.First then
								fire(on_updated_cbs, group[2])
							elseif #group == 1 then
								fire(on_removed_cbs, key)
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
					fire(on_updated_cbs, group[#group])
				elseif #group == 1 then
					fire(on_added_cbs, observed)
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
				elseif strategy == Observable.UniqueStrategy.Recent then
					local group = groups[new_key]
					if group then
						for i, entry in ipairs(group or {}) do
							if entry == observed then
								table.remove(group, i)
								break
							end
						end
						group[#group + 1] = observed
						fire(on_updated_cbs, observed)
					end
				end
			end

			local function on_removed(id)
				local key = key_for[id]
				remove_from_group(id, key)
			end

			observable.on_added(on_added)
			observable.on_updated(on_updated)
			observable.on_removed(on_removed)

			return {
				on_added = function(cb)
					table.insert(on_added_cbs, cb)
					return make_unsub(on_added_cbs, cb)
				end,
				on_updated = function(cb)
					table.insert(on_updated_cbs, cb)
					return make_unsub(on_updated_cbs, cb)
				end,
				on_removed = function(cb)
					table.insert(on_removed_cbs, cb)
					return make_unsub(on_removed_cbs, cb)
				end,
				all = function()
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
			}
		end,
	},
}

return setmetatable(Observable, {
	__call = function(self, inst)
		return setmetatable(inst, self.MT)
	end,
})
