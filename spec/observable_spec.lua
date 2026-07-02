require("spec.support.awesome_mocks")

local Observable = require("continuity.observable")
local Subscribable = require("continuity.class.subscribable")
local Removable = require("continuity.class.removable")
local class = require("continuity.class")

-- Creates a minimal item compatible with the internal API (Subscribable + Removable).
local Item = class.union("Item", Subscribable, Removable)
local function make_item(id)
	return Item.new({ id = id, state = nil })
end

describe("Observable", function()
	describe("internal API", function()
		local obs

		before_each(function()
			obs = Observable()
		end)

		describe("add", function()
			it("returns true on first add", function()
				local item = make_item("a")
				assert.is_true(obs:add(item))
			end)

			it("returns false when id already exists", function()
				local item = make_item("a")
				obs:add(item)
				assert.is_false(obs:add(item))
			end)

			it("item is accessible via get after add", function()
				local item = make_item("a")
				obs:add(item)
				assert.equals(item, obs:get("a"))
			end)

			it("fires on_added with the item", function()
				local item = make_item("a")
				local fired
				obs:on_added(function(h)
					fired = h
				end)
				obs:add(item)
				assert.equals(item, fired)
			end)

			it("does not fire on_added for a duplicate", function()
				local item = make_item("a")
				obs:add(item)
				local count = 0
				obs:on_added(function()
					count = count + 1
				end)
				obs:add(item)
				assert.equals(0, count)
			end)
		end)

		describe("update", function()
			it("returns false when id not found", function()
				assert.is_false(obs:update("missing", {}))
			end)

			it("calls push on the item with new state", function()
				local item = make_item("a")
				obs:add(item)
				obs:update("a", { level = 75 })
				assert.equals(75, item.state.level)
			end)

			it("fires on_updated with the item", function()
				local item = make_item("a")
				obs:add(item)
				local fired
				obs:on_updated(function(h)
					fired = h
				end)
				obs:update("a", { level = 50 })
				assert.equals(item, fired)
			end)
		end)

		describe("remove", function()
			it("returns nil when id not found", function()
				assert.is_nil(obs:remove("missing"))
			end)

			it("returns the item on success", function()
				local item = make_item("a")
				obs:add(item)
				assert.equals(item, obs:remove("a"))
			end)

			it("item is no longer accessible via get after remove", function()
				local item = make_item("a")
				obs:add(item)
				obs:remove("a")
				assert.is_nil(obs:get("a"))
			end)

			it("fires item _removed_cbs before clearing them", function()
				local item = make_item("a")
				obs:add(item)
				local received
				item:on_removed(function(id)
					received = id
				end)
				obs:remove("a")
				assert.equals("a", received)
			end)

			it("clears item _removed_cbs after firing", function()
				local item = make_item("a")
				obs:add(item)
				local count = 0
				item:on_removed(function()
					count = count + 1
				end)
				obs:remove("a")
				item:remove_event("a")
				assert.equals(1, count)
			end)

			it("clears item _subs after removal", function()
				local item = make_item("a")
				obs:add(item)
				item:subscribe(function() end)
				obs:remove("a")
				assert.equals(0, #item._subs)
			end)

			it("fires on_removed with the id", function()
				local item = make_item("a")
				obs:add(item)
				local received
				obs:on_removed(function(id)
					received = id
				end)
				obs:remove("a")
				assert.equals("a", received)
			end)

			it("item _removed_cbs fire before observable on_removed", function()
				local item = make_item("a")
				obs:add(item)
				local order = {}
				item:on_removed(function()
					order[#order + 1] = "item"
				end)
				obs:on_removed(function()
					order[#order + 1] = "obs"
				end)
				obs:remove("a")
				assert.same({ "item", "obs" }, order)
			end)
		end)

		describe("all", function()
			it("returns empty table when no items", function()
				assert.equals(0, #obs:all())
			end)

			it("returns all added items", function()
				obs:add(make_item("a"))
				obs:add(make_item("b"))
				assert.equals(2, #obs:all())
			end)

			it("does not include removed items", function()
				obs:add(make_item("a"))
				obs:add(make_item("b"))
				obs:remove("a")
				assert.equals(1, #obs:all())
			end)
		end)

		describe("get", function()
			it("returns nil for unknown id", function()
				assert.is_nil(obs:get("nope"))
			end)

			it("returns the item for a known id", function()
				local item = make_item("a")
				obs:add(item)
				assert.equals(item, obs:get("a"))
			end)
		end)

		describe("weak_on_added / weak_on_updated / weak_on_removed", function()
			it("weak_on_added fires on add while callback is held", function()
				local item = make_item("a")
				local fired
				local cb = function(h)
					fired = h
				end
				obs:weak_on_added(cb)
				obs:add(item)
				assert.equals(item, fired)
			end)

			it("weak_on_updated fires on update while callback is held", function()
				local item = make_item("a")
				obs:add(item)
				local fired
				local cb = function(h)
					fired = h
				end
				obs:weak_on_updated(cb)
				obs:update("a", {})
				assert.equals(item, fired)
			end)

			it("weak_on_removed fires on remove while callback is held", function()
				obs:add(make_item("a"))
				local received
				local cb = function(id)
					received = id
				end
				obs:weak_on_removed(cb)
				obs:remove("a")
				assert.equals("a", received)
			end)

			it("weak_on_added returns an unsubscribe function", function()
				local count = 0
				local cb = function()
					count = count + 1
				end
				local unsub = obs:weak_on_added(cb)
				obs:add(make_item("a"))
				unsub()
				obs:add(make_item("b"))
				assert.equals(1, count)
			end)

			it("weak_on_added does not fire after callback is collected", function()
				local fired = false
				local cb = function()
					fired = true
				end
				obs:weak_on_added(cb)
				cb = nil -- luacheck: ignore
				collectgarbage("collect")
				obs:add(make_item("a"))
				assert.is_false(fired)
			end)
		end)

		describe("debounce opts", function()
			local gears

			before_each(function()
				gears = require("gears")
				gears._created = {}
			end)

			describe("on_updated", function()
				it("coalesces rapid updates to the same item", function()
					local received = {}
					obs:add(make_item("a"))
					obs:on_updated(function(h)
						received[h.id] = h.state
					end, { debounce = 0.05 })
					obs:update("a", { v = 1 })
					obs:update("a", { v = 2 })
					obs:update("a", { v = 3 })
					assert.is_nil(received["a"])
					gears._created[1]:fire()
					assert.equals(3, received["a"].v)
				end)

				it("debounces items independently", function()
					local received = {}
					obs:add(make_item("a"))
					obs:add(make_item("b"))
					obs:on_updated(function(h)
						received[h.id] = (received[h.id] or 0) + 1
					end, { debounce = 0.05 })
					obs:update("a", { v = 1 })
					obs:update("b", { v = 2 })
					assert.is_nil(received["a"])
					assert.is_nil(received["b"])
					gears._created[1]:fire()
					assert.equals(1, received["a"])
					assert.is_nil(received["b"])
					gears._created[2]:fire()
					assert.equals(1, received["b"])
				end)

				it("remove before timer fires suppresses callback", function()
					local count = 0
					obs:add(make_item("a"))
					obs:on_updated(function()
						count = count + 1
					end, { debounce = 0.05 })
					obs:update("a", { v = 1 })
					obs:remove("a")
					gears._created[1]:fire()
					assert.equals(0, count)
				end)
			end)

			describe("on_added", function()
				it("fires once after settle", function()
					local count = 0
					local received = {}
					obs:on_added(function(item)
						count = count + 1
						received[item.id] = item
					end, { debounce = 0.05 })
					obs:add(make_item("a"))
					assert.equals(0, count)
					obs:update("a", { v = 1 })
					gears._created[1]:fire()
					assert.equals(1, count)
					assert.equals(1, received["a"].state.v)
				end)

				it("debounces items independently", function()
					local received = {}
					obs:on_added(function(h)
						received[h.id] = (received[h.id] or 0) + 1
					end, { debounce = 0.05 })
					obs:add(make_item("a"))
					obs:add(make_item("b"))
					assert.is_nil(received["a"])
					assert.is_nil(received["b"])
					gears._created[1]:fire()
					assert.equals(1, received["a"])
					assert.is_nil(received["b"])
					gears._created[2]:fire()
					assert.equals(1, received["b"])
				end)

				it("remove before timer fires suppresses callback", function()
					local count = 0
					obs:on_added(function()
						count = count + 1
					end, { debounce = 0.05 })
					obs:add(make_item("a"))
					obs:remove("a")
					gears._created[1]:fire()
					assert.equals(0, count)
				end)
			end)
		end)

		describe("on_added / on_updated / on_removed unsub", function()
			it("on_added unsub stops callbacks", function()
				local count = 0
				local unsub = obs:on_added(function()
					count = count + 1
				end)
				obs:add(make_item("a"))
				unsub()
				obs:add(make_item("b"))
				assert.equals(1, count)
			end)

			it("on_updated unsub stops callbacks", function()
				obs:add(make_item("a"))
				local count = 0
				local unsub = obs:on_updated(function()
					count = count + 1
				end)
				obs:update("a", {})
				unsub()
				obs:update("a", {})
				assert.equals(1, count)
			end)

			it("on_removed unsub stops callbacks", function()
				obs:add(make_item("a"))
				obs:add(make_item("b"))
				local count = 0
				local unsub = obs:on_removed(function()
					count = count + 1
				end)
				obs:remove("a")
				unsub()
				obs:remove("b")
				assert.equals(1, count)
			end)
		end)
	end)
end)
