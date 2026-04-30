local menubar_utils = require("menubar.utils")
local menu_gen = require("menubar.menu_gen")
local grep = require("continuity.tools.grep")
local find = require("continuity.tools.find")

local M = {}

---@type table<string, string|false>
local app_name_cache = {}
---@type table<string, string|false>
local desktop_entry_cache = {}

--- Resolve an icon path from an icon name.
---@param icon_name string The icon name.
---@param cb        fun(icon_path: string|nil)
function M.by_icon_name(icon_name, cb)
	cb(menubar_utils.lookup_icon(icon_name))
end

--- Resolve an icon path from an application name.
--- This attempts to discover a corresponding .desktop file based of the Name
--- field and extracts the icon name from it.
---@param app_name string The name of the application.
---@param cb       fun(icon_path: string|nil)
function M.by_app_name(app_name, cb)
	if app_name_cache[app_name] ~= nil then
		local icon_path = app_name_cache[app_name] and menubar_utils.lookup_icon(app_name_cache[app_name])
		cb(icon_path or nil)
		return
	end
	grep({
		pattern = "^Name=" .. app_name,
		path = menu_gen.all_menu_dirs,
		case_insensitive = true,
		follow_links = true,
		include = "*.desktop",
	}, function(results, _)
		if not results or #results == 0 then
			cb(nil)
			return
		end
		local desktop_file = results[1].filepath
		grep({
			pattern = "^Icon=",
			path = { desktop_file },
			follow_links = true,
		}, function(icon_results, _)
			if not icon_results or #icon_results == 0 then
				cb(nil)
				return
			end
			local icon_name = icon_results[1].text:match("^Icon=(.+)$")
			local icon_path = icon_name and menubar_utils.lookup_icon(icon_name) or nil
			app_name_cache[app_name] = icon_name or false
			cb(icon_path)
		end)
	end)
end

--- Resolve an icon path from a desktop entry stem.
--- This attempts to discover a corresponding .desktop file based the filename
--- and extracts the icon name from it.
---@param desktop_entry string The name of the desktop entry.
---@param cb            fun(icon_path: string|nil)
function M.by_desktop_entry(desktop_entry, cb)
	if desktop_entry_cache[desktop_entry] ~= nil then
		local icon_path = app_name_cache[desktop_entry] and menubar_utils.lookup_icon(app_name_cache[desktop_entry])
		cb(icon_path or nil)
		return
	end
	find({
		pattern = desktop_entry,
		type = "file",
		extension = "desktop",
		path = menu_gen.all_menu_dirs,
	}, function(results, _)
		if not results or #results == 0 then
			cb(nil)
			return
		end
		local desktop_file = results[1]
		grep({
			pattern = "^Icon=",
			path = { desktop_file },
			follow_links = true,
		}, function(icon_results, _)
			if not icon_results or #icon_results == 0 then
				cb(nil)
				return
			end
			local icon_name = icon_results[1].text:match("^Icon=(.+)$")
			local icon_path = icon_name and menubar_utils.lookup_icon(icon_name) or nil
			app_name_cache[desktop_entry] = icon_name or false
			cb(icon_path)
		end)
	end)
end

return M
