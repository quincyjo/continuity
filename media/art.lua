-- Art URI resolution and local cache.
-- Resolves art_uri values to local filesystem paths suitable for naughty icons.

local awful = require("awful")
local gears = require("gears")

local CACHE_DIR = os.getenv("HOME") .. "/.cache/awesome/media-art"
os.execute("mkdir -p " .. CACHE_DIR)
---@type table<string, string>
local cache = {} -- url -> local path

local art = {}

---@alias ArtCallback fun(local_path: string|nil)

--- Resolve art_uri to a local path, calling cb when ready.
--- nil         -> cb(nil) immediately
--- file:// URI -> strip prefix, cb(path) immediately
--- /...        -> cb(path) immediately (bare filesystem path, starts with "/")
--- https?://   -> download to cache dir, cb(path) or cb(nil) on failure
--- other       -> cb(nil) + warning logged
---@param art_uri string|nil
---@param cb ArtCallback
function art.resolve(art_uri, cb)
	if art_uri == nil then
		cb(nil)
		return
	end

	local file_path = art_uri:match("^file://(.+)$")
	if file_path then
		cb(file_path)
		return
	end

	if art_uri:match("^/") then
		cb(art_uri)
		return
	end

	if art_uri:match("^https?://") then
		if cache[art_uri] then
			cb(cache[art_uri])
			return
		end
		local filename = art_uri:gsub("[^%w]", "_") .. ".jpg"
		local dest = CACHE_DIR .. "/" .. filename
		local cmd = string.format("curl -s --max-time 5 -o %q %q", dest, art_uri)
		awful.spawn.easy_async({ "sh", "-c", cmd }, function(_, _, _, exitcode)
			if exitcode == 0 then
				cache[art_uri] = dest
				cb(dest)
			else
				gears.debug.print_warning("media.art: failed to download " .. art_uri)
				cb(nil)
			end
		end)
		return
	end

	gears.debug.print_warning("media.art: unknown URI scheme: " .. art_uri)
	cb(nil)
end

-- Test helpers.
function art._clear_cache()
	cache = {}
end
function art._inject_cache(url, path)
	cache[url] = path
end

return art
