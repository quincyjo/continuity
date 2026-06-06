---@generic T: Subscribable, Removable
---@class Observable<T>
---@field on_added        fun(self: Observable<T>, cb: fun(handle: T)): fun()
---@field on_updated      fun(self: Observable<T>, cb: fun(handle: T)): fun()
---@field on_removed      fun(self: Observable<T>, cb: fun(id: string)): fun()
---@field weak_on_added   fun(self: Observable<T>, cb: fun(handle: T)): fun()
---@field weak_on_updated fun(self: Observable<T>, cb: fun(handle: T)): fun()
---@field weak_on_removed fun(self: Observable<T>, cb: fun(id: string)): fun()
---@field all             fun(self: Observable<T>): T[]
---@field get             fun(self: Observable<T>, id: string): T|nil
---@field group_by        fun(self: Observable<T>, group_by: fun(observed: T): `K`): Observable<Group<`K`, T>>
---@field unique          fun(self: Observable<T>, unique_by: fun(observed: T): `K`, strategy: nil|UniqueStrategy): Observable<T>

---@generic S, T: Subscribable<S>, Removable
---@class ObservableInternal<T, S> : Observable<T>
---@field items  table<string, T>
---@field add    fun(self: Observable<T>, item: T): boolean
---@field update fun(self: Observable<T>, id: string, state: S): boolean
---@field remove fun(self: Observable<T>, id: string): T|nil

local Subscribable = require("continuity.subscribable")
local Subscriptions = require("continuity.util.subscriptions")

---@class ObservableClass
---@generic T, S
---@overload fun(inst?: table): ObservableInternal<T, S>
local Observable = {}

---@enum UniqueStrategy
Observable.UniqueStrategy = {
	First = "first",
	Last = "last",
	Recent = "recent",
}

Observable.MT = {
	__index = {
		on_added = function(self, cb)
			return self._on_added_cbs:add(cb)
		end,

		on_updated = function(self, cb)
			return self._on_updated_cbs:add(cb)
		end,

		on_removed = function(self, cb)
			return self._on_removed_cbs:add(cb)
		end,

		weak_on_added = function(self, cb)
			return self._on_added_cbs:weak_add(cb)
		end,

		weak_on_updated = function(self, cb)
			return self._on_updated_cbs:weak_add(cb)
		end,

		weak_on_removed = function(self, cb)
			return self._on_removed_cbs:weak_add(cb)
		end,

		add = function(self, item)
			if self.items[item.id] then
				return false
			end
			self.items[item.id] = item
			self._on_added_cbs:fire(item)
			return true
		end,

		update = function(self, id, state)
			local item = self.items[id]
			if not item then
				return false
			end
			item:push(state)
			self._on_updated_cbs:fire(item)
			return true
		end,

		remove = function(self, id)
			local item = self.items[id]
			if not item then
				return nil
			end
			item:remove_event(id)
			Subscribable.init(item)
			self.items[id] = nil
			self._on_removed_cbs:fire(id)
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

		---@generic T, K
		---@param self Observable<T>
		---@param group_by fun(observed: T): K
		---@return Observable<Group<K, T>>
		group_by = function(self, group_by)
			return require("continuity.observable.transformation.group_by").new(self, group_by)
		end,

		---@generic T, K
		---@param self Observable<T>
		---@param unique_by fun(observed: T): K
		---@param strategy? UniqueStrategy
		---@return Observable<T>
		unique = function(self, unique_by, strategy)
			return require("continuity.observable.transformation.unique").new(self, unique_by, strategy)
		end,

		---@generic T, S
		---@param self Observable<T>
		---@param mapper fun(observed: T): S
		---@return Observable<S>
		map = function(self, mapper)
			return require("continuity.observable.transformation.map").new(self, mapper)
		end,

		---@generic T, S
		---@param self Observable<T>
		---@param mapper fun(observed: T): S[]
		---@return Observable<S>
		flatmap = function(self, mapper)
			return require("continuity.observable.transformation.flatmap").new(self, mapper)
		end,

		---@generic T
		---@param self Observable<T>
		---@param predicate fun(observed: T): boolean
		---@return Observable<T>
		filter = function(self, predicate)
			return require("continuity.observable.transformation.filter").new(self, predicate)
		end,
	},
}

function Observable.init(inst)
	inst = inst or {}
	inst._on_added_cbs = Subscriptions()
	inst._on_updated_cbs = Subscriptions()
	inst._on_removed_cbs = Subscriptions()
	inst.items = {}
	return inst
end

function Observable.new(inst)
	return setmetatable(Observable.init(inst), Observable.MT)
end

---@diagnostic disable-next-line: param-type-mismatch
setmetatable(Observable, {
	__call = function(self, inst)
		return self.new(inst)
	end,
})

return Observable
