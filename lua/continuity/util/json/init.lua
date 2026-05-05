--- If luarocks lua-json c extension is installed and luarocks are loaded, use
--- it. Otherwise, use json.lua lua module by rxi.

local ok, c_json = pcall(require, "json")
if ok then
	return c_json
else
	return require("continuity.util.json.json_lua")
end
