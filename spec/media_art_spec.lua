require("spec.support.awesome_mocks")

-- Ensure the real art module is loaded, not any mock set by another spec.
package.preload["continuity.media.art"] = nil
package.loaded["continuity.media.art"] = nil

local awful = require("awful")
local gears = require("gears")
local last_cmd, warned

awful.spawn.easy_async = function(cmd, _cb)
	last_cmd = type(cmd) == "table" and table.concat(cmd, " ") or cmd
end

gears.debug.print_warning = function()
	warned = true
end

local art = require("continuity.media.art")

describe("art.resolve", function()
	before_each(function()
		last_cmd = nil
		warned = false
		art._clear_cache()
	end)

	it("calls back with nil for nil input", function()
		local result = "not_called"
		art.resolve(nil, function(p)
			result = p
		end)
		assert.is_nil(result)
	end)

	it("strips file:// prefix and calls back immediately", function()
		local result
		art.resolve("file:///home/user/music/cover.jpg", function(p)
			result = p
		end)
		assert.equals("/home/user/music/cover.jpg", result)
	end)

	it("passes bare filesystem path through immediately", function()
		local result
		art.resolve("/home/user/music/cover.jpg", function(p)
			result = p
		end)
		assert.equals("/home/user/music/cover.jpg", result)
	end)

	it("triggers curl download for https:// URL", function()
		art.resolve("https://i.scdn.co/image/abc123", function() end)
		assert.is_not_nil(last_cmd)
		assert.truthy(last_cmd:match("curl"))
		assert.truthy(last_cmd:match("https://i.scdn.co/image/abc123"))
	end)

	it("triggers curl download for http:// URL", function()
		art.resolve("http://example.com/cover.jpg", function() end)
		assert.is_not_nil(last_cmd)
		assert.truthy(last_cmd:match("curl"))
	end)

	it("calls back with nil and logs warning for unknown URI scheme", function()
		local result = "not_called"
		art.resolve("ftp://example.com/cover.jpg", function(p)
			result = p
		end)
		assert.is_nil(result)
		assert.is_true(warned)
	end)

	it("returns cached path immediately on second call — no curl", function()
		art._inject_cache("https://example.com/art.jpg", "/tmp/cached.jpg")
		last_cmd = nil
		local result
		art.resolve("https://example.com/art.jpg", function(p)
			result = p
		end)
		assert.is_nil(last_cmd)
		assert.equals("/tmp/cached.jpg", result)
	end)
end)
