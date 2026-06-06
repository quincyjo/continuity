require("spec.support.awesome_mocks")

local Observable = require("continuity.observable")
local Subscribable = require("continuity.subscribable")
local Removable = require("continuity.removable")
local extend = require("continuity.util.extend")

local Item = extend(Subscribable, Removable)
local function make_item(id, state)
	return setmetatable(Item.init({ id = id, state = state }), Item.MT)
end

local function make_observable()
	local obs = Observable()
	return obs,
		function(item)
			obs.on_added_cbs:fire(item)
			obs.weak_on_added_cbs:fire(item)
		end,
		function(item)
			obs.on_updated_cbs:fire(item)
			obs.weak_on_updated_cbs:fire(item)
		end,
		function(id)
			obs.on_removed_cbs:fire(id)
			obs.weak_on_removed_cbs:fire(id)
		end
end

describe("Observable", function()
	describe("flatmap", function()
		local obs, add, update, remove

		before_each(function()
			obs, add, update, remove = make_observable()
		end)

		describe("on_added", function()
			it("fires once per output item", function()
				local flat = obs:flatmap(function(item)
					return {
						make_item(item.id .. "_1", item.state),
						make_item(item.id .. "_2", item.state),
					}
				end)
				local fired = {}
				flat:on_added(function(item)
					fired[#fired + 1] = item.id
				end)

				add(make_item("a", 1))

				assert.equals(2, #fired)
			end)

			it("wraps plain table outputs", function()
				local flat = obs:flatmap(function(item)
					return { { id = item.id .. "_1", state = item.state } }
				end)
				local fired
				flat:on_added(function(item)
					fired = item
				end)

				add(make_item("a", 1))

				assert.is_not_nil(fired)
				assert.is_function(fired.subscribe)
				assert.is_function(fired.on_removed)
			end)

			it("fires separately for each source item", function()
				local flat = obs:flatmap(function(item)
					return { make_item(item.id .. "_1", item.state) }
				end)
				local count = 0
				flat:on_added(function()
					count = count + 1
				end)

				add(make_item("a", 1))
				add(make_item("b", 2))

				assert.equals(2, count)
			end)
		end)

		describe("on_updated", function()
			it("fires on_updated for output ids present in both old and new", function()
				local item_a = make_item("a", { "x", "y" })
				local flat = obs:flatmap(function(item)
					local result = {}
					for _, v in ipairs(item.state) do
						result[#result + 1] = make_item(v, item.id)
					end
					return result
				end)
				add(item_a)

				local updated_ids = {}
				flat:on_updated(function(item)
					updated_ids[#updated_ids + 1] = item.id
				end)

				update(make_item("a", { "x", "z" }))

				local found = false
				for _, id in ipairs(updated_ids) do
					if id == "x" then
						found = true
					end
				end
				assert.is_true(found)
			end)

			it("fires on_removed for output ids dropped from new mapping", function()
				local item_a = make_item("a", { "x", "y" })
				local flat = obs:flatmap(function(item)
					local result = {}
					for _, v in ipairs(item.state) do
						result[#result + 1] = make_item(v, item.id)
					end
					return result
				end)
				add(item_a)

				local removed_ids = {}
				flat:on_removed(function(id)
					removed_ids[#removed_ids + 1] = id
				end)

				update(make_item("a", { "x" }))

				assert.equals(1, #removed_ids)
				assert.equals("y", removed_ids[1])
			end)

			it("fires on_added for output ids new in updated mapping", function()
				local item_a = make_item("a", { "x" })
				local flat = obs:flatmap(function(item)
					local result = {}
					for _, v in ipairs(item.state) do
						result[#result + 1] = make_item(v, item.id)
					end
					return result
				end)
				add(item_a)

				local added_ids = {}
				flat:on_added(function(item)
					added_ids[#added_ids + 1] = item.id
				end)

				update(make_item("a", { "x", "z" }))

				assert.equals(1, #added_ids)
				assert.equals("z", added_ids[1])
			end)

			it("does not fire on_added or on_removed for unchanged ids", function()
				local item_a = make_item("a", { "x", "y" })
				local flat = obs:flatmap(function(item)
					local result = {}
					for _, v in ipairs(item.state) do
						result[#result + 1] = make_item(v, item.id)
					end
					return result
				end)
				add(item_a)

				local add_count, remove_count = 0, 0
				flat:on_added(function()
					add_count = add_count + 1
				end)
				flat:on_removed(function()
					remove_count = remove_count + 1
				end)

				update(make_item("a", { "x", "y" }))

				assert.equals(0, add_count)
				assert.equals(0, remove_count)
			end)
		end)

		describe("on_removed", function()
			it("fires for each output item when source is removed", function()
				local flat = obs:flatmap(function(item)
					return {
						make_item(item.id .. "_1", item.state),
						make_item(item.id .. "_2", item.state),
					}
				end)
				add(make_item("a", 1))

				local removed_ids = {}
				flat:on_removed(function(id)
					removed_ids[#removed_ids + 1] = id
				end)

				remove("a")

				assert.equals(2, #removed_ids)
			end)

			it("does not fire for output items of a different source", function()
				local flat = obs:flatmap(function(item)
					return { make_item(item.id .. "_1", item.state) }
				end)
				add(make_item("a", 1))
				add(make_item("b", 2))

				local removed_ids = {}
				flat:on_removed(function(id)
					removed_ids[#removed_ids + 1] = id
				end)

				remove("a")

				assert.equals(1, #removed_ids)
				assert.equals("a_1", removed_ids[1])
			end)
		end)
	end)
end)
