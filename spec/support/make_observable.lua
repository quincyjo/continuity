local Observable = require("continuity.observable")
local Subscribable = require("continuity.class.subscribable")
local Removable = require("continuity.class.removable")
local class = require("continuity.class")

local Item = class.union("Item", Subscribable, Removable)

local function make_item(id, state)
	return Item.new({ id = id, state = state })
end

local function make_observable()
	local obs = Observable()
	return obs,
		function(item)
			obs:add(item)
		end,
		function(id, state)
			obs:update(id, state)
		end,
		function(id)
			obs:remove(id)
		end
end

return {
	make_item = make_item,
	make_observable = make_observable,
}
