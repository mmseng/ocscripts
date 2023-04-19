local component = require("component")
local robot = require("robot")
local r = component.robot

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
end

while(true) do
	r.suck(3)
	
	if(needDrop()) then
		dropAll()
	end
end