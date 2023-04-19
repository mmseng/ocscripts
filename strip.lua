local component = require("component")
local robot = require("robot")
local sides = require("sides")
local r = component.robot

local function log(msg)
	io.write(msg)
end

function needDrop()
	
	-- Count empty slots
	local emptySlots = 0
	for slot = 1, 16 do
	  if robot.count(slot) == 0 then
	    emptySlots = emptySlots + 1
	  end
	end
	
	if (emptySlots < 1) then
		return true
	end
	
	return false
end

local function dropAll()
	log("    Dropping...")
	for slot = 1, 16 do
		if robot.count(slot) > 0 then
			robot.select(slot)
			local wait = 1
			repeat
				if not robot.dropDown() then
					os.sleep(wait)
					wait = math.min(10, wait + 1)
				end
			until robot.count(slot) == 0
		end
	end
	log("        Done dropping...")
end

log("Starting loop...")
while(true) do
	log("\nStarting loop iteration...")
	log("    Sucking...")
	r.suck(sides.forward)
	log("        Done sucking.")
	
	log("    Checking if full...")
	if(needDrop()) then
	    log("        Full.")
		dropAll()
	else
		log("        Not full.")
	end
	log("Done with loop iteration.")
end