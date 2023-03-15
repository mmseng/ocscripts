local arg = { ... }
local file = arg[1] .. ".lua"
local url = "https://raw.githubusercontent.com/mmseng/ocscripts/master/" .. file
local path = "/home/" .. file

local shell = require("shell")
shell.execute("wget -f " .. url .. " " .. file)
