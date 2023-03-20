function log(msg)
	io.write(msg)
end

local c = require("component")
local cl = c.chunkloader
local state
local newState

state = cl.isActive()
if state then
	log("Chunkloader is currently active. Setting to inactive...\n")
	cl.setActive(false)
	newState = cl.isActive()
	if newState then
		log("	Failed to set chunkloader to inactive!\n")
	else
		log("	Successfully set chunkloader to inactive.\n")
	end
else
	log("Chunkloader is currently inactive. Setting to active...\n")
	cl.setActive(true)
	newState = cl.isActive()
	if newState then
		log("	Successfully set chunkloader to active.\n")
	else
		log("	Failed to set chunkloader to active!\n")
	end
end