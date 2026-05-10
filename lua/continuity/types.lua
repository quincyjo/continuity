---@class Subscribable<T>
---@field subscribe fun(self, cb: fun(state: T)): fun()

---@class Monitor<T> : Subscribable<T>
---@field state T|nil
---@field stop  fun()

---@class ReadyAware<T> : Subscribable<T>
---@field on_ready fun(self, cb: fun(state: T))

---@class Controllable<T>
---@field on_control fun(self, cb: fun(state: T)): fun()

---@class Observable<T>
---@field on_added   fun(self, cb: fun(handle: T)): fun()
---@field on_updated fun(self, cb: fun(handle: T)): fun()
---@field on_removed fun(self, cb: fun(id: string)): fun()
---@field all        fun(self): T[]

return {}
