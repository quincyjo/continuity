local ObservableTransformation = {}

---@generic T, S
---@param origin Observable<T>
---@param transformation Observable<S>
---@param binding { on_added: fun(observed: T), on_updated: fun(observed: T), on_removed: fun(id: string) }
---@return Observable<S>
function ObservableTransformation.new(origin, transformation, binding)
	for _, observed in pairs(origin:all()) do
		binding.on_added(observed)
	end

	origin:on_added(binding.on_added)
	origin:on_updated(binding.on_updated)
	origin:on_removed(binding.on_removed)

	return transformation
end

return setmetatable(ObservableTransformation, {
	__call = function(self, ...)
		return self.new(...)
	end,
})
