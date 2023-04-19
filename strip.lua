local component = require("component")
local robot = require("robot")
local sides = require("sides")
local r = component.robot

local function log(msg)
	io.write(msg .. "\n")
end

log("Starting loop...")

while(true) do
	log("\nStarting loop iteration...")
	for slot = 1, 16 do
		log("    Sucking...")
		r.suck(sides.forward)
		log("    Dropping slot " .. slot .. "...")
		robot.select(slot)
		robot.dropDown()
	end
	log("Done with loop iteration.")
end