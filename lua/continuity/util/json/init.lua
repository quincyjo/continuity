--- If lua-cjson c extension is installed and luarocks are loaded, use
--- it. Otherwise, use json.lua lua module by rxi.

---@class Json
---@field is_c_extension boolean         True if using lua-cjson
---@field encode fun(value: any): string Encode a lua value into a JSON string.
---@field decode fun(str: string): any   Decode a string into a lua value.
---@field null   any                     Json null sentinal.
local json
local ok
ok, json = pcall(require, "cjson")
if ok then
	json.is_c_extension = true
else
	json = require("continuity.util.json.json_lua")
	json.null = nil
	json.is_c_extension = false
end

return json
