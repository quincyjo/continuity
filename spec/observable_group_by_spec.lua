require("spec.support.awesome_mocks")

local support = require("spec.support.make_observable")
local make_item = support.make_item
local make_observable = support.make_observable

describe("Observable", function()
	describe("group_by", function()
		local obs, add, update, remove

		before_each(function()
			obs, add, update, remove = make_observable()
		end)

		describe("on_added", function()
			it("fires when the first item for a key is added", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				local fired
				grouped:on_added(function(group)
					fired = group
				end)

				add(make_item("a", "sink"))

				assert.is_not_nil(fired)
			end)

			it("fires with correct group id and state", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				local fired
				grouped:on_added(function(group)
					fired = group
				end)

				add(make_item("a", "sink"))

				assert.equals("sink", fired.id)
				assert.equals(1, #fired.state)
				assert.equals("a", fired.state[1].id)
			end)

			it("fires separately for each new key", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				local fired = {}
				grouped:on_added(function(group)
					fired[#fired + 1] = group.id
				end)

				add(make_item("a", "sink"))
				add(make_item("b", "source"))

				assert.equals(2, #fired)
			end)

			it("does not fire when a second item is added to an existing group", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				local count = 0
				grouped:on_added(function()
					count = count + 1
				end)

				add(make_item("a", "sink"))
				add(make_item("b", "sink"))

				assert.equals(1, count)
			end)
		end)

		describe("on_updated", function()
			it("fires when a second item is added to an existing group", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				local fired
				grouped:on_updated(function(group)
					fired = group
				end)

				add(make_item("a", "sink"))
				add(make_item("b", "sink"))

				assert.is_not_nil(fired)
				assert.equals("sink", fired.id)
				assert.equals(2, #fired.state)
			end)

			it("does not fire when the first item for a key is added", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				local called = false
				grouped:on_updated(function()
					called = true
				end)

				add(make_item("a", "sink"))

				assert.is_false(called)
			end)

			it("fires when an item is removed from a group that still has other items", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "sink"))

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
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "sink"))

				local fired_ids = {}
				grouped:on_updated(function(group)
					fired_ids[#fired_ids + 1] = group.id
				end)
				grouped:on_added(function(group)
					fired_ids[#fired_ids + 1] = group.id
				end)

				update("a", "source")

				-- "sink" group still has item b → on_updated("sink")
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
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "sink"))

				local added_key
				grouped:on_added(function(group)
					added_key = group.id
				end)

				update("a", "source")

				assert.equals("source", added_key)
			end)
		end)

		describe("on_removed", function()
			it("fires with the group key when the last item is removed", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))

				local removed_key
				grouped:on_removed(function(key)
					removed_key = key
				end)

				remove("a")

				assert.equals("sink", removed_key)
			end)

			it("does not fire when group still has items after removal", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "sink"))

				local called = false
				grouped:on_removed(function()
					called = true
				end)

				remove("a")

				assert.is_false(called)
			end)

			it("fires on_removed for old key when the last item moves to a different key", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))

				local removed_key
				grouped:on_removed(function(key)
					removed_key = key
				end)

				update("a", "source")

				assert.equals("sink", removed_key)
			end)
		end)

		describe("all()", function()
			it("returns empty table when no items have been added", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				assert.equals(0, #grouped:all())
			end)

			it("returns one group per distinct key", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "sink"))
				add(make_item("c", "source"))

				assert.equals(2, #grouped:all())
			end)

			it("each group contains the correct state", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "sink"))

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
					return item.state
				end)
				add(make_item("a", "sink"))

				local group = grouped:get("sink")
				assert.is_not_nil(group)
				assert.equals("sink", group.id)
			end)

			it("returns nil for an unknown key", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				assert.is_nil(grouped:get("does_not_exist"))
			end)

			it("returned group reflects subsequent additions", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				local group = grouped:get("sink")
				add(make_item("b", "sink"))

				assert.equals(2, #group.state)
			end)
		end)

		describe("group:subscribe", function()
			it("fires when a second item is added to the group", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				local group = grouped:get("sink")

				local fired
				group:subscribe(function(g)
					fired = g
				end)

				add(make_item("b", "sink"))

				assert.is_not_nil(fired)
				assert.equals(2, #fired)
			end)

			it("fires when an item is removed from the group but the group survives", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "sink"))
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
					return item.state
				end)

				local called = false
				grouped:on_added(function(group)
					group:subscribe(function()
						called = true
					end)
				end)

				add(make_item("a", "sink"))

				assert.is_false(called)
			end)

			it("supports multiple independent subscribers on the same group", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				local group = grouped:get("sink")

				local count_a, count_b = 0, 0
				group:subscribe(function()
					count_a = count_a + 1
				end)
				group:subscribe(function()
					count_b = count_b + 1
				end)

				add(make_item("b", "sink"))

				assert.equals(1, count_a)
				assert.equals(1, count_b)
			end)

			it("unsubscribing stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				local group = grouped:get("sink")

				local count = 0
				local unsub = group:subscribe(function()
					count = count + 1
				end)

				add(make_item("b", "sink"))
				unsub()
				add(make_item("c", "sink"))

				assert.equals(1, count)
			end)
		end)

		describe("unsubscribe", function()
			it("on_added unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				local count = 0
				local unsub = grouped:on_added(function()
					count = count + 1
				end)

				add(make_item("a", "sink"))
				unsub()
				add(make_item("b", "source"))

				assert.equals(1, count)
			end)

			it("on_updated unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))

				local count = 0
				local unsub = grouped:on_updated(function()
					count = count + 1
				end)

				add(make_item("b", "sink"))
				unsub()
				add(make_item("c", "sink"))

				assert.equals(1, count)
			end)

			it("on_removed unsub stops further callbacks", function()
				local grouped = obs:group_by(function(item)
					return item.state
				end)
				add(make_item("a", "sink"))
				add(make_item("b", "source"))

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
