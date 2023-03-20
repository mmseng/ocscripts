function log(msg)
	io.write(msg)
end

local c = require("component")
local cl = c.chunkloader

local state = cl.isActive()
local newState
if state then
	log("Chunkloader is currently active. Setting to inactive...")
	cl.setActive(false)
	newState = cl.isActive()
	if newState then
		log("	Failed to set chunkloader to inactive!")
	else
		log("	Successfully set chunkloader to inactive.")
	end
else
	log("Chunkloader is currently inactive. Setting to active..."
	cl.setActive(true)
	newState = cl.isActive()
	if newState then
		log("	Successfully set chunkloader to active.")
	else
		log("	Failed to set chunkloader to active!")
	end
end