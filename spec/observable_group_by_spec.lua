require("spec.support.awesome_mocks")

local Observable = require("continuity.observable")

local function make_observable()
	local function fire(cbs, ...)
		for _, cb in pairs(cbs) do
			cb(...)
		end
	end

	local obs = Observable()

	return obs,
		function(item)
			fire(obs.on_added_cbs, item)
		end,
		function(item)
			fire(obs.on_updated_cbs, item)
		end,
		function(id)
			fire(obs.on_removed_cbs, id)
		end
end

describe("Observable", function()
	describe("group_by", function()
		local obs, add, update, remove

		before_each(function()
			obs, add, update, remove = make_observable()
		end)

		describe("on_added", function()
			it("fires when the first item for a key is added", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired
				grouped:on_added(function(group)
					fired = group
				end)

				add({ id = "a", kind = "sink" })

				assert.is_not_nil(fired)
			end)

			it("fires with correct group id and state", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired
				grouped:on_added(function(group)
					fired = group
				end)

				add({ id = "a", kind = "sink" })

				assert.equals("sink", fired.id)
				assert.equals(1, #fired.state)
				assert.equals("a", fired.state[1].id)
			end)

			it("fires separately for each new key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired = {}
				grouped:on_added(function(group)
					fired[#fired + 1] = group.id
				end)

				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "source" })

				assert.equals(2, #fired)
			end)

			it("does not fire when a second item is added to an existing group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local count = 0
				grouped:on_added(function()
					count = count + 1
				end)

				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				assert.equals(1, count)
			end)
		end)

		describe("on_updated", function()
			it("fires when a second item is added to an existing group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local fired
				grouped:on_updated(function(group)
					fired = group
				end)

				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				assert.is_not_nil(fired)
				assert.equals("sink", fired.id)
				assert.equals(2, #fired.state)
			end)

			it("does not fire when the first item for a key is added", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local called = false
				grouped:on_updated(function()
					called = true
				end)

				add({ id = "a", kind = "sink" })

				assert.is_false(called)
			end)

			it("fires when an item is removed from a group that still has other items", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				local fired
				grouped:on_updated(function(group)
					fired = group
				end)

				remove("a")

				assert.is_not_nil(fired)
				assert.equals("sink", fired.id)
				assert.equals(1, #fired.state)
			end)

			it("fires for old group when an item moves to a different key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local item_a = { id = "a", kind = "sink" }
				local item_b = { id = "b", kind = "sink" }
				add(item_a)
				add(item_b)

				local fired_ids = {}
				grouped:on_updated(function(group)
					fired_ids[#fired_ids + 1] = group.id
				end)
				grouped:on_added(function(group)
					fired_ids[#fired_ids + 1] = group.id
				end)

				item_a.kind = "source"
				update(item_a)

				-- "sink" group still has item_b → on_updated("sink")
				-- "source" is a new group → on_added("source")
				assert.is_true(#fired_ids >= 1)
				local found_sink = false
				for _, id in ipairs(fired_ids) do
					if id == "sink" then
						found_sink = true
					end
				end
				assert.is_true(found_sink)
			end)

			it("fires on_added for new key when an item moves", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local item_a = { id = "a", kind = "sink" }
				local item_b = { id = "b", kind = "sink" }
				add(item_a)
				add(item_b)

				local added_key
				grouped:on_added(function(group)
					added_key = group.id
				end)

				item_a.kind = "source"
				update(item_a)

				assert.equals("source", added_key)
			end)
		end)

		describe("on_removed", function()
			it("fires with the group key when the last item is removed", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })

				local removed_key
				grouped:on_removed(function(key)
					removed_key = key
				end)

				remove("a")

				assert.equals("sink", removed_key)
			end)

			it("does not fire when group still has items after removal", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				local called = false
				grouped:on_removed(function()
					called = true
				end)

				remove("a")

				assert.is_false(called)
			end)

			it("fires on_removed for old key when the last item moves to a different key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local item_a = { id = "a", kind = "sink" }
				add(item_a)

				local removed_key
				grouped:on_removed(function(key)
					removed_key = key
				end)

				item_a.kind = "source"
				update(item_a)

				assert.equals("sink", removed_key)
			end)
		end)

		describe("all()", function()
			it("returns empty table when no items have been added", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				assert.equals(0, #grouped:all())
			end)

			it("returns one group per distinct key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })
				add({ id = "c", kind = "source" })

				assert.equals(2, #grouped:all())
			end)

			it("each group contains the correct state", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })

				local groups = grouped:all()
				local sink_group
				for _, g in ipairs(groups) do
					if g.id == "sink" then
						sink_group = g
					end
				end
				assert.is_not_nil(sink_group)
				assert.equals(2, #sink_group.state)
			end)
		end)

		describe("get()", function()
			it("returns the group for a known key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })

				local group = grouped:get("sink")
				assert.is_not_nil(group)
				assert.equals("sink", group.id)
			end)

			it("returns nil for an unknown key", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				assert.is_nil(grouped:get("does_not_exist"))
			end)

			it("returned group reflects subsequent additions", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")
				add({ id = "b", kind = "sink" })

				assert.equals(2, #group.state)
			end)
		end)

		describe("group:subscribe", function()
			it("fires when a second item is added to the group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")

				local fired
				group:subscribe(function(g)
					fired = g
				end)

				add({ id = "b", kind = "sink" })

				assert.is_not_nil(fired)
				assert.equals(2, #fired)
			end)

			it("fires when an item is removed from the group but the group survives", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "sink" })
				local group = grouped:get("sink")

				local fired
				group:subscribe(function(g)
					fired = g
				end)

				remove("a")

				assert.is_not_nil(fired)
				assert.equals(1, #fired)
			end)

			it("does not fire when the first item is added (group just created)", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)

				local called = false
				grouped:on_added(function(group)
					group:subscribe(function()
						called = true
					end)
				end)

				add({ id = "a", kind = "sink" })

				assert.is_false(called)
			end)

			it("supports multiple independent subscribers on the same group", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")

				local count_a, count_b = 0, 0
				group:subscribe(function()
					count_a = count_a + 1
				end)
				group:subscribe(function()
					count_b = count_b + 1
				end)

				add({ id = "b", kind = "sink" })

				assert.equals(1, count_a)
				assert.equals(1, count_b)
			end)

			it("unsubscribing stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				local group = grouped:get("sink")

				local count = 0
				local unsub = group:subscribe(function()
					count = count + 1
				end)

				add({ id = "b", kind = "sink" })
				unsub()
				add({ id = "c", kind = "sink" })

				assert.equals(1, count)
			end)
		end)

		describe("unsubscribe", function()
			it("on_added unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				local count = 0
				local unsub = grouped:on_added(function()
					count = count + 1
				end)

				add({ id = "a", kind = "sink" })
				unsub()
				add({ id = "b", kind = "source" })

				assert.equals(1, count)
			end)

			it("on_updated unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })

				local count = 0
				local unsub = grouped:on_updated(function()
					count = count + 1
				end)

				add({ id = "b", kind = "sink" })
				unsub()
				add({ id = "c", kind = "sink" })

				assert.equals(1, count)
			end)

			it("on_removed unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.kind
				end)
				add({ id = "a", kind = "sink" })
				add({ id = "b", kind = "source" })

				local count = 0
				local unsub = grouped:on_removed(function()
					count = count + 1
				end)

				remove("a")
				unsub()
				remove("b")

				assert.equals(1, count)
			end)
		end)
	end)
end)
