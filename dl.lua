local arg = { ... }
local file = arg[1]
local url = "https://raw.githubusercontent.com/mmseng/ocscripts/master/" .. file
local path = "/home/" .. file

-- If path exists, get length of file
-- TODO: change this to getting the whole file as a string and compare actual content (i.e. diff)
--local exists = 
--local length = 0
--if exists then
	-- length = 
--end

-- Download file and overwrite
local shell = require("shell")
shell.execute("wget -f " .. url .. " " .. file)

-- Check length of new file and warn if length hasn't changed
--local newLength = 
--if length == newLength then
	--io.write("Warning: new file is the same length as overwritten file."
--end