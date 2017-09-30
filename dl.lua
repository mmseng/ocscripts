local arg = { ... }
local file = arg[1] .. ".lua"
local url = "http://www.theroach.net/minecraft/ocscripts/" .. file
local path = "/home/" .. file

local shell = require("shell")
shell.execute("wget -f " .. url .. " " .. file)
