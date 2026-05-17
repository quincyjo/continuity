---@generic T: Subscribable, Removable
---@class Observable<T>
---@field on_added   fun(self: Observable<T>, cb: fun(handle: T)): fun()
---@field on_updated fun(self: Observable<T>, cb: fun(handle: T)): fun()
---@field on_removed fun(self: Observable<T>, cb: fun(id: string)): fun()
---@field all        fun(self: Observable<T>): T[]
---@field get        fun(self: Observable<T>, id: string): T|nil
---@field group_by   fun(self: Observable<T>, group_by: fun(observed: T): `K`): Observable<Group<`K`, T>>
---@field unique     fun(self: Observable<T>, unique_by: fun(observed: T): `K`, strategy: nil|UniqueStrategy): Observable<T>

---@generic T: Subscribable<S>, Removable
---@class ObservableInternal<T, S> : Observable<T>
---@field add    fun(self: Observable<T>, item: T): boolean
---@field update fun(self: Observable<T>, id: string, state: S): boolean
---@field remove fun(self: Observable<T>, id: string): T|nil

---@class Group<K, T> : Subscribable<T[]>
---@field id K
---@field entries T[]

local Subscribable = require("continuity.subscribable")
local Removable = require("continuity.removable")

local Observable = {}

---@enum UniqueStrategy
Observable.UniqueStrategy = {
	First = "first",
	Last = "last",
	Recent = "recent",
}

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

Observable.MT = {
	__index = {
		on_added = function(self, cb)
			self.on_added_cbs[#self.on_added_cbs + 1] = cb
			return make_unsub(self.on_added_cbs, cb)
		end,

		on_updated = function(self, cb)
			self.on_updated_cbs[#self.on_updated_cbs + 1] = cb
			return make_unsub(self.on_updated_cbs, cb)
		end,

		on_removed = function(self, cb)
			self.on_removed_cbs[#self.on_removed_cbs + 1] = cb
			return make_unsub(self.on_removed_cbs, cb)
		end,

		add = function(self, item)
			if self.items[item.id] then
				return false
			end
			self.items[item.id] = item
			fire(self.on_added_cbs, item)
			return true
		end,

		update = function(self, id, state)
			local item = self.items[id]
			if not item then
				return false
			end
			item:push(state)
			fire(self.on_updated_cbs, item)
			return true
		end,

		remove = function(self, id)
			local item = self.items[id]
			if not item then
				return nil
			end
			fire(item._removed_cbs or {}, id)
			Subscribable.init(item)
			Removable.init(item)
			self.items[id] = nil
			fire(self.on_removed_cbs, id)
			return item
		end,

		all = function(self)
			local result = {}
			for _, item in pairs(self.items) do
				result[#result + 1] = item
			end
			return result
		end,

		get = function(self, id)
			return self.items[id]
		end,

		---@param observable Observable<`T`>
		---@param group_by fun(observed: `T`): `K`
		---@return Observable<Group<`K`, `T`>>
		group_by = function(observable, group_by)
			local self = Observable({})
			---@type table<`K`, fun(group: Group<`K`, `T`>)[]>
			local group_subscribers = {}
			---@type table<string, `K`>
			local group_for = {}

			local groupMT = {
				__index = {
					subscribe = function(group, cb)
						local key = group.id
						if not group_subscribers[key] then
							group_subscribers[key] = {}
						end
						local cbs = group_subscribers[key]
						cbs[#cbs + 1] = cb
						return make_unsub(cbs, cb)
					end,
				},
			}

			---@param id string
			---@param key `K`
			local function remove_from_group(id, key)
				group_for[id] = nil
				local group = self.items[key]
				if group then
					for i, entry in ipairs(group.entries) do
						if entry.id == id then
							table.remove(group.entries, i)
							break
						end
					end
					if #group.entries == 0 then
						self.items[key] = nil
						group_subscribers[key] = nil
						fire(self.on_removed_cbs, key)
					else
						fire(self.on_updated_cbs, group)
						fire(group_subscribers[key] or {}, group.entries)
					end
				end
			end

			local function add_to_group(observed, key)
				group_for[observed.id] = key
				local group = self.items[key]
				if not group then
					group = setmetatable({ id = key, entries = { observed } }, groupMT)
					self.items[key] = group
				else
					table.insert(group.entries, observed)
				end
				if #group.entries == 1 then
					fire(self.on_added_cbs, group)
				else
					fire(self.on_updated_cbs, group)
					fire(group_subscribers[key] or {}, group.entries)
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

			for _, observed in pairs(observable:all()) do
				on_added(observed)
			end

			observable:on_added(on_added)
			observable:on_updated(on_updated)
			observable:on_removed(on_removed)

			return self
		end,

		---@param observable Observable<`T`>
		---@param unique_by fun(observed: `T`): `K`
		---@param strategy? UniqueStrategy
		---@return Observable<`T`>
		unique = function(observable, unique_by, strategy)
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
								and (
									strategy == Observable.UniqueStrategy.Last
									or strategy == Observable.UniqueStrategy.Recent
								)
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

			for _, observed in pairs(observable:all()) do
				on_added(observed)
			end

			observable:on_added(on_added)
			observable:on_updated(on_updated)
			observable:on_removed(on_removed)

			return self
		end,
	},
}

function Observable.init(inst)
	inst = inst or {}
	inst.on_added_cbs = {}
	inst.on_updated_cbs = {}
	inst.on_removed_cbs = {}
	inst.items = {}
	return inst
end

---@generic T, S
---@overload fun(inst: table): ObservableInternal<T, S>
return setmetatable(Observable, {
	__call = function(self, inst)
		return setmetatable(self.init(inst), self.MT)
	end,
})
