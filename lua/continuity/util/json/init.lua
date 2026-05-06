--- If luarocks lua-json c extension is installed and luarocks are loaded, use
--- it. Otherwise, use json.lua lua module by rxi.

---@class Json
---@field is_c_extension boolean
---@field encode fun(value: any): string
---@field decode fun(str: string): any

local ok, json = pcall(require, "json")
if ok then
	json.is_c_extension = true
else
	json = require("continuity.util.json.json_lua")
	json.is_c_extension = false
end

---@type Json
return json
