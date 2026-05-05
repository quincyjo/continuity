--- If luarocks lua-json c extension is installed and luarocks are loaded, use
--- it. Otherwise, use json.lua lua module by rxi.

local ok, c_json = pcall(require, "json")
if ok then
	c_json.is_c_extension = true
	return c_json
else
	local lua_native = require("continuity.util.json.json_lua")
	lua_native.is_c_extension = false
	return lua_native
end
