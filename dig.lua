--[[

==============
dig2.lua
v1.1
by Roachy
==============

------------
Description
------------
This is an overhaul of the dig.lua program included with OpenComputers.

----------
Changelog
----------
	v1.1:
		- Added configurable depth/width/height
			Use -S option for original behavior (square shaft to bedrock)
			Use new -C option for digging a cube
		- Added -j option for "jumping to" a layer (skipping higher layers)
		- Overhauled and fleshed out failure logic and added text output for relevant occurrences
		- Overhauled organization of functions to reduce duplication of code and logic
		- Added energy monitoring. Will return to origin when energy drains below a reasonable threshhold.

------
Plans
------
	- Add option to discard cobble/stone
	- Add failure recovery techniques (e.g. can't hover high enough so move to wall)
	- Add ability to specify where on the outskirts of the dig the chest and/or charger block are located
	- Re-implement logic to continue next layer without returning to origin corner (temporarily removed for simplicity)
	- Add/overhaul argument parsing logic
	- Add ability to refuel via generator upgrade if present
	- Add check for chunk loading upgrade, and disable it after completing the dig
	- Add more compatibility checks for various components and upgrades
	- Improve usage message formatting or font size to better fit screen
	
------
Usage
------
	- Robot is placed in one corner of the dig
	- The robot's starting position is y=0, x=0, z=0, f=0
	- The starting position is included in volume of the dig
	- From there, the robot will dig:
		(<depth>  - 1) blocks in the +y direction (forward)
		(<width>  - 1) blocks in the +x direction (right)
		(<height> - 1) blocks in the +z direction (down)

y=<depth>   +---------------+
    ^       |       0       |
    |       |               |
    |       |       ^       |
    |       |  3  < f >  1  |
    |       |       v       |
    |       |               |
    |       ^       2       |
   y=0     ER---------------+
            C
   
           x=0 ----------> x=<width>

	Legend:
		R = Robot starting position
		C = Chest behind robot will be used to dump inventory
		E = Suggested location for energy source (charger block). Could also be above the robot.

]]

--===========
-- Variables
--===========

-----------------------------------------
-- Include libraries/wrappers/components
-----------------------------------------
local component = require("component")
local computer = require("computer")
local robot = require("robot")
local shell = require("shell")
local sides = require("sides")
local r = component.robot

local args, options = shell.parse(...)

-----------------------
-- Energy calculations
-----------------------

-- Max energy the robot can hold
local maxEnergy = computer.maxEnergy()

-- These are set in the OpenComputers config
-- May we could pull them programmatically somehow?
local energyUsedPerMove = 15
local energyUsedPerBlockBroken = 2.5
--local energyUsedPerTurn = 2.5
--local energyUserPerTick = 0.25

-- avgBlocksBrokenPerMove and minEnergyReserveBuffer are for used for estimating how much energy to keep in reserve for making sure we make it home
-- Raise to be more conservative if we find ourselves running out of energy before making it home
-- Lower to minimize unneccesary trips home

-- For estimating how much energy will be spent on breaking blocks on the way home
local avgBlocksBrokenPerMove = 0.2

-- How close (in percent of maxEnergy) we want to approach to the minimum energy level to keep
-- (i.e. maxEnergyNeededToReturnHome) before returning home
local minEnergyReserveBuffer = 0.05

-- Calculated based on max distance to home, energyUsedPerMove, avgBlocksBrokenPerMove, and energyUsedPerBlockBroken
local maxEnergyNeededToReturnHome

-- Calculated based on maxEnergyNeededToReturnHome and minEnergyReserveBuffer
local minEnergyReserve

-------------------------------
-- Position/direction tracking
-------------------------------

-- y = forward and back (depth)
-- x = left and right (width)
-- z = up and down (height)
-- f = direction we're facing compared to original direction
	-- 0 = forward (positive y)
	-- 1 = right (positive x)
	-- 2 = back (negative y)
	-- 3 = left (negative x)
local y, x, z, f = 0, 0, 0, 0
local returningHome = false -- avoid recursing into returnHome()
local delta = {
	[0] = function() y = y + 1 end,
	[1] = function() x = x + 1 end,
	[2] = function() y = y - 1 end,
	[3] = function() x = x - 1 end
}

-----------------------
-- Dimension arguments
-----------------------
local size, depth, width, height
local jumpTo = 0
local maxHeight = 256 -- Max height of world, for use with options that dig maximum height holes (down to bedrock)

--===========
-- Functions
--===========

-- Print usage
local function usage()
	io.write("Usage:\n")
	io.write("	dig [-s] <depth> <width> <height>\n")
	io.write("	dig [-s] -j <depth> <width> <height> <jump_to>\n")
	io.write("	dig [-s] -C <cubic_size>\n")
	io.write("	dig [-s] -S <square_size>\n")
	io.write("\n")
	
	io.write("Examples:\n")
	io.write("	dig 7 11 5\n")
	io.write("	dig -sj 7 11 5 4\n")
	io.write("	dig -s -C 9\n")
	io.write("\n")
	
	io.write("Options:\n")
	io.write("	-s: Shutdown when done.\n")
	io.write("		Compatible with all other options.\n")
	io.write("	-j: Jump to the layer specified by <jump_to> within the area specified by the other 3 arguments (all required) and dig onward from there.\n")
	io.write("		e.g. if <jump_to> is 5 the robot will start digging layers 5, 6, and 7 (unless <height> is less than 6 or 7).\n")
	io.write("		Not compatible with -S or -C.\n")
	io.write("	-S: Dig a square of size <square_size> to bedrock.\n")
	io.write("		Actually digs down a number of layers equal to the maximum world height configured via the maxHeight variable (currently " .. maxHeight .."), until hitting bedrock.\n")
	io.write("		Not compatible with -j or -C.\n")
	io.write("	-C: Dig a cube of size <cubic_size>.\n")
	io.write("		Not compatible with -j or -S.\n")
	io.write("	Note: options can be specified together or separately. See examples.\n")
	io.write("\n")
	
	io.write("Arguments:\n")
	io.write("	<depth>: The horizontal forward distance to dig (in the direction robot is facing when placed).\n")
	io.write("	<width>: The horizontal rightward distance to dig (as seen from above, the robot starts off in the bottom of the leftmost \"column\").\n")
	io.write("	<height>: The vertical (x) distance to dig downward (most energy efficient if divisible by 3).\n")
	io.write("	<jump_to>: If option -j is given, the robot will move to this layer and dig onward from there.\n")
	io.write("	<square_size>: If option -S is given, this value is used for <depth> and <width>. <height> is set to the max world height (configurable via maxHeight variable).\n")
	io.write("	<cubic_size>: If option -C is given, this value is used for <depth>, <width>, and <height>.\n")
	io.write("\n")
	
	io.write("Robot placement:\n")
	io.write("	See comments at top of script.\n")
	io.write("\n")
end

-- Turn right and track the direction we're facing
local function turnRight()
	robot.turnRight()
	f = (f + 1) % 4
end

-- Turn left and track the direction we're facing
local function turnLeft()
	robot.turnLeft()
	f = (f - 1) % 4
end

local function turnTowards(side)
	if f == side - 1 then
	  turnRight()
	else
	  while f ~= side do
	    turnLeft()
	  end
	end
end

local function turn(i)
	if i % 2 == 1 then
	  turnRight()
	else
	  turnLeft()
	end
end

local function clearBlock(side, cannotRetry)
	while r.suck(side) do
	  statusCheck()
	end
	local result, reason = r.swing(side)
	if result then
	  statusCheck()
	else
		local _, what = r.detect(side)
		if cannotRetry then
			if what == "air" then
				-- io.stderr:write("Error: Could not clear air block from relative position y=" .. y .. ", x=" .. x .. ", z=" .. z .. ", f=" .. f .. ". Are we at the flight height limit?\n")
				io.stderr:write("Error: Could not clear air block at " .. sides[side] .. " side. Are we at the flight height limit?\n")
			elseif what == "entity" then
				io.stderr:write("Error: Could not clear entity at side: " .. side .. ".\n")	
			else
				io.stderr:write("Error: Could not clear block (" .. what .. ") from side: " .. side .. ".\n")
			end
			return false
		end
	end
	return true
end

local function tryMove(side)
	side = side or sides.forward
	local tries = 5
	while not r.move(side) do
	  tries = tries - 1
	  if not clearBlock(side, tries < 1) then
	    return false
	  end
	end
	if side == sides.down then
	  z = z + 1
	elseif side == sides.up then
	  z = z - 1
	else
	  delta[f]()
	end
	return true
end

local function moveTo(ty, tx, tz, backwards)
	local axes = {
		function()
			local direction
			if z > tz then
				direction = sides.up
			elseif z < tz then
				direction = sides.down
			end
			while z ~= tz do
				if not tryMove(direction) then
					io.stderr:write("Error: Failed to move " .. sides[direction] .. " during moveTo.\n")
					return false
				end
			end
			return true
		end,
		function()
			if x > tx then
				turnTowards(3)
				--repeat tryMove() until x == tx
			elseif x < tx then
				turnTowards(1)
				--repeat tryMove() until x == tx
			end
			while x ~= tx do
				if not tryMove() then
					io.stderr:write("Error: Failed to move in x direction during moveTo.\n")
					return false
				end
			end
			return true
		end,
		function()
			if y > ty then
				turnTowards(2)
				--repeat tryMove() until y == ty
			elseif y < ty then
				turnTowards(0)
				--repeat tryMove() until y == ty
			end
			while y ~= ty do
				if not tryMove() then
					io.stderr:write("Error: Failed to move in y direction during moveTo.\n")
					return false
				end
			end
			return true
		end
	}
	if backwards then
		for axis = 3, 1, -1 do
			if not axes[axis]() then
				return false
			end
		end
	else
		for axis = 1, 3 do
			if not axes[axis]() then
				return false
			end
		end
	end
	return true
end

local function isEnergyFull()	
	local energy = computer.energy()
	local leeway = 20
	if energy < (maxEnergy - leeway) then
		return false
	end
	return true
end

local function dropAll()
	io.write("Dropping inventory...")
	for slot = 1, 16 do
		if robot.count(slot) > 0 then
			robot.select(slot)
			local wait = 1
			repeat
				if not robot.drop() then
					os.sleep(wait)
					wait = math.min(10, wait + 1)
				end
			until robot.count(slot) == 0
		end
	end
	robot.select(1)
	io.write(" done.\n")
end

local function returnHome()
	returningHome = true
	io.write("Returning home...\n")
	
	if not moveTo(0, 0, 0) then
		io.write("Error: Failed returning home.\n")
		return false
	else	
		io.write("Finished returning home.\n")
	end
	
	-- Drop off inventory
	turnTowards(2)
	dropAll()
	turnTowards(0)
	
	-- Wait for energy to charge
	io.write("Waiting to charge...")
	while not isEnergyFull() do
		os.sleep(1)
	end
	io.write(" done.\n")
	
	returningHome = false
	return true
end

function homeAndBack()
	-- Save current position
	local oy, ox, oz, of = y, x, z, f

	-- Return Home
	if not returnHome() then
		return false
	end

	-- Return to mining at saved position
	io.write("Returning to y=" .. oy .. ", x=" .. ox .. ", z=" .. oz .. ", f=" .. of .. "...\n")
	if not moveTo(oy, ox, oz, true) then
		io.stderr:write("Error: Failed to return to position.\n")
		return false
	else
		turnTowards(of)
		io.write("Returned to position.\n")
	end
	return true
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
		io.write("Drop needed, no free inventory slots.\n")
		return true
	end
	
	return false
end

function needEnergy()
	
	-- Get remaining energy
	local energy = math.floor(computer.energy())
	
	-- If remaining energy is at or below the minimum amount of energy we want to have in reserve
	if(energy <= minEnergyReserve) then
		io.write("Energy needed. Current: " .. energy.. "/" .. maxEnergy .. ", needed: " .. maxEnergyNeededToReturnHome .. ", preferred reserve: " .. minEnergyReserve .. ".\n")
		return true
	end
	return false
end

function statusCheck()
	if not returningHome then
		if needEnergy() or needDrop() then
			homeAndBack()
		end
	end
end

local function calculateEnergyNeeds()

	-- Very approximately, we shall assume that every block moved requires
	-- using enough energy to:
		-- move one block and
		-- break 1/Xth of a block on average.
	-- This should give us a reasonably conservative estimate for energy required per block move.
	
	local maxDistToReturnHome = width + depth + height
	io.write("Max distance to home calculated as: " .. maxDistToReturnHome .. ".\n")
	
	-- energyUsedToMove should conservatively be the actual maximum,
	-- to account for when the robot is at the end of the dig
	local energyUsedToMove = energyUsedPerMove * maxDistToReturnHome
	
	-- However energyUsedToBreakBlocks can be a percentage, because usually, you're not
	-- breaking many blocks on the return trip (unless you use option -j to skip downward)
	-- TODO: add logic to modify avgBlocksBrokenPerMove (or energyUsedToBreakBlocks) if -j option was specified
	-- to account for more blocks being broken when returning home
	local energyUsedToBreakBlocks = energyUsedPerBlockBroken * maxDistToReturnHome
	energyUsedToBreakBlocks = energyUsedToBreakBlocks * avgBlocksBrokenPerMove
		
	maxEnergyNeededToReturnHome = energyUsedToMove + energyUsedToBreakBlocks	
	io.write("Max energy needed to return home calculated as: " .. maxEnergyNeededToReturnHome .. "/" .. maxEnergy .. ".\n")
	
	minEnergyReserve = (maxEnergy * minEnergyReserveBuffer) + maxEnergyNeededToReturnHome
	io.write("Min energy reserve to keep calculated as: " .. minEnergyReserve .. "/" .. maxEnergy .. ".\n")
end

-- Advance one space
local function step(thickness)
	
	if (thickness > 1) then
		-- Clear block below
		if not clearBlock(sides.down) then
			io.stderr:write("Error: Could not complete step (clearing below).\n")
			return false
		end
	end
	
	-- Clear block in front and move forward
	if not tryMove() then
		io.stderr:write("Error: Could not complete step (moving forward).\n")
		return false
	end
	
	if(thickness > 2) then
		-- Clear block above
		if not clearBlock(sides.up) then
			io.stderr:write("Error: Could not complete step (clearing above).\n")
			return false
		end
	end
	
	return true
end

local function digLayer(thickness)

	thickness = thickness or 3

	-- For each "column"
	for col = 1, width do
	
		-- For each "row"
		for row = 1, depth - 1 do
			-- Try moving forward
			if not step(thickness) then
				return false
			end
		end
		-- At end of column
		
		-- If this is not the last column, move to the next column
		if col < width then
			-- If this is an odd column, turn right, move forward, turn right
			if((col % 2) == 1) then
				turnRight()
				if not step(thickness) then
					return false
				end
				turnRight()
			-- If even column, turn left, move forward, turn left
			else
				turnLeft()
				if not step(thickness) then
					return false
				end
				turnLeft()
			end		
	
		-- If this IS the last column, the loop should exit
		end
	end
	
	-- Return to starting position in that layer
	
	-- If width is odd, we'll be at the far corner from 0,0 and facing forward
	if((width % 2) == 1) then
		-- Move to "bottom right" corner
		turnRight()
		turnRight()
		for i = 1, (depth - 1) do
			if not step(thickness) then
				return false
			end
		end
	end
			
	-- If width is even we'll already be at the "bottom right" corner, facing backwards
	turnRight()
	for i = 1, (width - 1) do
		if not step(thickness) then
			return false
		end
	end
	turnRight()
	
	return true
end

local function digLayers()

	-- Dig layers 
	local layersLeft = height
	local layersDug = 0
	local justJumped = false
	local currentLayer = 0
	
	-- Jump to specified layer
	if options.j then
		if not moveTo(0, 0, (jumpTo - 1)) then -- (jumpTo - 1) because the layers are 0-indexed
			io.stderr:write("Error: Failed jumping to specified layer.\n")
			return false
		end
		layersDug = jumpTo - 1
		layersLeft = height - layersDug
		justJumped = true
	end
	
	while (layersLeft > 0) do
		
		currentLayer = layersDug + 1

		-- Move into position for next layer		
		
		-- If there's only one layer left
		if (layersLeft == 1) then
		
			-- If this is the first and only layer, or the first layer jumped to via option -j
			if((height < 2) or (justJumped)) then
				justJumped = false
				-- stay in starting position
				--io.write("This is the only layer, staying on this layer.\n")
			-- If this is not the only layer
			else
				-- move down into the final layer
				--io.write("Only one layer left, moving to last layer.\n")
				if not tryMove(sides.down) then
					io.stderr:write("Error: Failed to move into position for new layer (1).\n")
					return false
				end
			end
			
			-- Dig a 1-tall layer at current height, ignoring layers above and below
			io.write("Digging 1-tall layer (#" .. currentLayer .. ")...\n")
			if not digLayer(1) then
				io.stderr:write("Error: Could not complete 1-tall layer (#" .. currentLayer .. ").\n")
				return false
			end
			layersDug = layersDug + 1
		
		-- If there's only two layers left
		elseif (layersLeft == 2) then
		
			-- If these are the first and only two layers, or first two layers jumped to via option -j
			if((height < 3) or (justJumped)) then
				justJumped = false
				-- stay in starting position
				--io.write("These are the only two layers, staying on this layer.\n")
			
			-- If these are not the only two layers
			else
				-- move down into the first of the two final layers
				--io.write("Only two layers left, moving to the first of the two layers.\n")
				if not tryMove(sides.down) then
					io.stderr:write("Error: Failed to move into position for new layer (2).\n")
					return false
				end
			end
			
			-- Dig a 2-tall layer at current height, ignoring the layer above
			io.write("Digging 2-tall layer (#" .. currentLayer .. "-" .. (currentLayer + 1) .. ")...\n")
			if not digLayer(2) then
				io.stderr:write("Error: Could not complete 2-tall layer (#" .. currentLayer .. "-" .. (currentLayer + 1) .. ")...\n")
				return false
			end
			layersDug = layersDug + 2
			
		-- If there's 3 or more layers left
		else
			-- If these are the first 3 layers, or the first 3 layers jumped to via option -j
			if ((layersDug < 1) or (justJumped)) then
				justJumped = false

				-- move down into the middle layer
				--io.write("These are the first three layers, moving to the middle layer.\n")
				if not tryMove(sides.down) then
					io.stderr:write("Error: Failed to move into position for new layer (3).\n")
					return false
				end
				
			-- If these are not the first 3 layers	
			else
			
				-- move down further into the actual middle layer
				--io.write("Three or more layers left, moving to the middle layer.\n")
				for i = 1, 3 do
					if not tryMove(sides.down) then
						io.stderr:write("Error: Failed to move into position for new layer (4).\n")
						return false
					end
				end
			end
			
			-- Dig a 3-tall layer at current height, including the layers above and below
			io.write("Digging 3-tall layer (#" .. currentLayer .. "-" .. (currentLayer + 2) .. ")...\n")
			if not digLayer() then
				io.stderr:write("Error: Could not complete 3-tall layer (#" .. currentLayer .. "-" .. (currentLayer + 2) .. ")...\n")
				return false
			end
			layersDug = layersDug + 3
		end
		
		layersLeft = height - layersDug
		io.write("Done digging layer(s). " .. layersDug .. " layers dug total. " .. layersLeft .. "/" .. height .. " layers left.\n")
	end
	return true
end

-- Parse arguments and options
-- Print usage and exit if invalid
local function parseArgs()
	if #args < 1 then
		return false
	end
	
	-- TODO: add logic for invalid argument combinations

	if options.C then
		size = tonumber(args[1])
		if not size then
			io.stderr:write("Error: Invalid value for <cubic_size>.\n")
			return false
		end
		depth = size
		width= size
		height = size
	elseif options.S then
		size = tonumber(args[1])
		if not size then
			io.stderr:write("Error: Invalid value for <square_size>.\n")
			return false
		end
		depth = size
		width= size
		height = maxHeight
	else
		depth = tonumber(args[1])
		if not depth then
			io.stderr:write("Error: Invalid value for <depth>.\n")
			return false
		end
		width = tonumber(args[2])
		if not width then
			io.stderr:write("Error: Invalid value for <width>.\n")
			return false
		end
		height = tonumber(args[3])
		if not height then
			io.write("Invalid or null value for <height>, setting to max height (" .. maxHeight .. ").\n")
			height = maxHeight
		else
			if options.j then
				jumpTo = tonumber(args[4])
				if not jumpTo then
					io.stderr:write("Error: Invalid value for <jump_to>.\n")
					return false
				end
			end
		end	
		
	end
	
	local confirm = "Digging hole of depth=" .. depth .. ", width= " .. width .. ", height=" .. height .. ".\n" 
	if (options.j) then
		confirm = confirm .. " Starting at layer " .. jumpTo .. " (" .. (jumpTo - 1) .. " layers skipped).\n"
	end	
	
	io.write(confirm .. "\n")
	return true
end

local function checkCompat()

	if not component.isAvailable("robot") then
		io.stderr:write("Error: Can only run on robots.\n")
		return false
	end
	
	-- TODO: Check for generator upgrade
	
	return true
end

--==============
-- Begin script
--==============

-- Check compatibility
if not checkCompat() then
	io.stderr:write("Error: Compatibility checks failed.\n")
	return
end

-- Parse args
if not parseArgs() then
	io.stderr:write("Error: Failed to parse arguments.\n")
	usage()
	return
end

calculateEnergyNeeds()

-- Dig layers
if not digLayers() then
	io.stderr:write("Error: Failed to dig all layers.\n")
end

-- Return home
returnHome()

-- Shutdown if specified
if options.s then
	io.write("Shutting down...\n")
	computer.shutdown()
end