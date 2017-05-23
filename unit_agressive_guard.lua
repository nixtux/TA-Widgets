function widget:GetInfo()
	return {
		name	= "Aggressive Guard",
		desc	= "guards rather than follows",
		author  = "zoggop",
		date 	= "March 2012",
		license	= "whatever",
		layer 	= 0,
		enabled	= true
	}
end

-- if the guarded unit's parameter is a unitID, use the unitID's position rather than the guarded unit's velocity

-- clean up gameframe code (there's a lot of redundant get positions, for one thing)

local forwardDistance = 200 -- this should probably scale with the guarded unit's speed (this could be done simply by not normalizing the velocity vector)
local sideDistance = 60 -- and this with the unit's size
local minPatrolUnits = 1

local rotateHeading = (2^16) / (forwardDistance / 20)
local totalRotations = math.floor( (2^16) / rotateHeading ) - 1
local convoyDistance = math.sqrt( (forwardDistance^2) + (sideDistance^2) ) + 150
local sizeX = Game.mapSizeX 
local sizeZ = Game.mapSizeZ

local guardSide = {}
local toughness = {}
local elmoSize = {}
local baseXZ = {}
local numGuarding = {}
local guarderHeading = {}


-- local functions

local function getAggressive() -- pun intended
	for uDefID, uDef in pairs(UnitDefs) do
		local tough = 0
		if uDef.canAttack and uDef.canMove then
			local cost = uDef.metalCost
			tough = uDef.health / cost
		end
		if uDef.isBuilder then
			toughness[uDefID] = 0
		else
			toughness[uDefID] = tough
		end
		elmoSize[uDefID] = (uDef.xsize + uDef.zsize) * 4 -- not the best place to put this...
--		Spring.Echo(uDef.name, uDef.humanName, uDef.tooltip, cost, tough)
	end
end

local function constrainToMap(x, z)
	x = math.max(math.min(x, sizeX), 0)
	z = math.max(math.min(z, sizeZ), 0)
	return x, z
end

local function normalizeVector(vx, vz)
	local dist = math.sqrt( (vx^2) + (vz^2) )
	vx = vx / dist
	vz = vz / dist
	return vx, vz
end

local function forwardPositions(unitID, vx, vz)
	local nvx, nvz
	local uDefID = Spring.GetUnitDefID(unitID)
	local smult = sideDistance + elmoSize[uDefID]
	local x, y, z = Spring.GetUnitPosition(unitID)
	local cq = Spring.GetUnitCommands(unitID, 1)
	local useMoveVector = false
	local pvx, pvz
	local cmdParams
	if cq[1] then
		if cq[1].params then
			cmdParams = cq[1].params
			if #cmdParams == 3 then useMoveVector = true end
		end
	end
	if useMoveVector then
		local dx = cmdParams[1] - x
		local dz = cmdParams[3] - z
		local d = math.sqrt( (dx^2) + (dz^2) )
		dx = dx / d
		dz = dz / d
		local vd = math.sqrt( (math.abs(vx)^2) + (math.abs(vz)^2) )
--		Spring.Echo("using move vector", dx, dz, vd)
		nvx = dx * vd
		nvz = dz * vd
		local nvd = math.sqrt( (math.abs(nvx)^2) + (math.abs(nvz)^2) )
		if nvd*smult > d then
			-- if the distance to the new forward point is larger than the distance to the guarded unit's target, then use the target instead
			x = cmdParams[1]
			z = cmdParams[3]
			pvx = { -nvz, nvz }
			pvz = { nvx, -nvx }
			nvx = 0
			nvz = 0
		end
	else
--		Spring.Echo("using velocity", vx, vz)
		nvx, nvz = vx, vz
	end
	if not pvx then
		pvx = { -nvz, nvz }
		pvz = { nvx, -nvx }
	end
	local fx1 = x + (nvx*forwardDistance) + (pvx[1]*smult)
	local fz1 = z + (nvz*forwardDistance) + (pvz[1]*smult)
	fx1, fz1 = constrainToMap(fx1, fz1)
	local fy1 = Spring.GetGroundHeight(fx1, fz1)
	local fx2 = x + (nvx*forwardDistance) + (pvx[2]*smult)
	local fz2 = z + (nvz*forwardDistance) + (pvz[2]*smult)
	fx2, fz2 = constrainToMap(fx2, fz2)
	local fy2 = Spring.GetGroundHeight(fx2, fz2)
	return { {x = fx1, y = fy1, z = fz1}, {x = fx2, y = fy2, z = fz2} }
end

local function twoDimensionalDistance(x1, z1, x2, z2)
	local dx = math.abs( x1 - x2 )
	local dz = math.abs( z1 - z2 )
	local d = math.sqrt( (dx^2) + (dz^2) )
	return d
end

local function getBaseXZ()
	local xSum = 0
	local zSum = 0
	local costSum = 0
	local units = Spring.GetTeamUnits(myTeam)
	for i, uID in pairs(units) do
		local uDefID = Spring.GetUnitDefID(uID)
		local uDef = UnitDefs[uDefID]
		if uDef.isBuilding and not uDef.canMove then
			local x, y, z = Spring.GetUnitPosition(uID)
			local cost = uDef.metalCost
			xSum = xSum + (x*cost)
			zSum = zSum + (z*cost)
			costSum = costSum + cost
		end
	end
	if costSum > 0 then
		local xAvg = xSum / costSum
		local zAvg = zSum / costSum
		return { x = xAvg, z = zAvg }
	else
		--if no buildings found, use the position of the most costly unit
		local highestCost = 0
		local x, y, z
		for i, uID in pairs(units) do
			local uDefID = Spring.GetUnitDefID(uID)
			local uDef = UnitDefs[uDefID]
			local cost = uDef.metalCost
			if cost > highestCost then
				x, y, z = Spring.GetUnitPosition(uID)
				highestCost = cost
			end
		end
		return { x = x, z = z }
	end
end


-- callins

function widget:Initialize()
	getAggressive()
	myTeam = Spring.GetMyTeamID()
	baseXZ = getBaseXZ()
end

function widget:GameStart()
	baseXZ = getBaseXZ()
end

function widget:GameFrame(gf)

	if gf % 30 == 0 then
		local fpos = {}
		local alreadyStopped = {}
		local guardingCount = {}
		local units = Spring.GetTeamUnits(myTeam)
		for i, uID in pairs(units) do
			local cq = Spring.GetUnitCommands(uID, 1)
			if cq[1] then
				if cq[1].id == CMD.GUARD then
					local tID = cq[1].params[1]
					local tDefID = Spring.GetUnitDefID(tID)
					local gDefID = Spring.GetUnitDefID(uID)
					if  (toughness[gDefID] > toughness[tDefID]) or ( (toughness[gDefID] > 0) and (UnitDefs[gDefID].maxWeaponRange < UnitDefs[tDefID].maxWeaponRange) ) then
						--if guarding unit is appropriate to guard the guarded unit aggreessively, do so
						local vx, vy, vz = Spring.GetUnitVelocity(tID)
						if (math.abs(vx) > 0) or (math.abs(vz) > 0) then
							-- if guarded unit is moving, move in front of it
							if not fpos[tID] then
								fpos[tID] = forwardPositions(tID, vx, vz)
							end
							local s
							if not guardSide[uID] then
								s = math.random(1, 2)
								guardSide[uID] = { s = s, tID = tID }
							elseif guardSide[uID].tID ~= tID then
								s = math.random(1, 2)
								guardSide[uID] = { s = s, tID = tID }
							else
								s = guardSide[uID].s
							end
							Spring.GiveOrderToUnit( uID, CMD.FIGHT, {fpos[tID][s].x, fpos[tID][s].y, fpos[tID][s].z}, {} )
							Spring.GiveOrderToUnit( uID, CMD.GUARD, {tID}, {"shift"} )
							
							-- calculate distance between guarder and guarded, if it exceeds convoyDistance, then delay guarded unit
							local tx, ty, tz = Spring.GetUnitPosition(tID)
							local ux, uy, uz = Spring.GetUnitPosition(uID)
							local dx = ux - tx
							local dz = uz - tz
							local d = math.sqrt( (math.abs(dx)^2) + (math.abs(dz)^2) )
							if d > convoyDistance and not alreadyStopped[tID] then
								local sx = tx + (dx / 4)
								local sz = tz + (dz / 4)
								sx, sz = constrainToMap(sx, sz)
								local sy = Spring.GetGroundHeight(sx, sz)
								Spring.GiveOrderToUnit( tID, CMD.INSERT, {0, CMD.MOVE, CMD.OPT_SHIFT, sx, sy, sz}, {"alt"} )
								alreadyStopped[tID] = true
							end
							
						else
							if not numGuarding[tID] then numGuarding[tID] = 0 end
							if numGuarding[tID] < minPatrolUnits then
								-- if guarded unit is standing still and there are not enough units to circle-patrol, move to the side opposite your base
								local x, y, z = Spring.GetUnitPosition(tID)
								local bdx = baseXZ.x - x
								local bdz = baseXZ.z - z
								local bvx, bvz = normalizeVector(bdx, bdz)
								local evx, evz = -bvx, -bvz
								local fx = x + (evx*forwardDistance) + (sideDistance*(1-(math.random()*2)))
								local fz = z + (evz*forwardDistance) + (sideDistance*(1-(math.random()*2)))
								fx, fz = constrainToMap(fx, fz)
								local fy = Spring.GetGroundHeight(fx, fz)
								Spring.GiveOrderToUnit( uID, CMD.FIGHT, {fx, fy, fz}, {} )
								Spring.GiveOrderToUnit( uID, CMD.GUARD, {tID}, {"shift"} )
							else
								-- if there are enough to circle-patrol, do so
								if not guarderHeading[uID] then
									guarderHeading[uID] = math.random(-32767, 32767)
								end
								local h = guarderHeading[uID]
								local x, y, z = Spring.GetUnitPosition(tID)
--								local i = 0
--								repeat
									local rvx, rvz = Spring.GetVectorFromHeading(h)
									local fx = x + (rvx*forwardDistance)
									local fz = z + (rvz*forwardDistance)
									fx, fz = constrainToMap(fx, fz)
									local fy = Spring.GetGroundHeight(fx, fz)
									Spring.GiveOrderToUnit( uID, CMD.FIGHT, {fx, fy, fz}, {} )
--									h = h + rotateHeading
--									if h > 32767 then h = h - 65534 end
--									i = i + 1
--								until i == totalRotations
								Spring.GiveOrderToUnit( uID, CMD.GUARD, {tID}, {"shift"} )
								guarderHeading[uID] = guarderHeading[uID] + rotateHeading
							end
						end
						if not guardingCount[tID] then guardingCount[tID] = 0 end
						guardingCount[tID] = guardingCount[tID] + 1
					end
				end
			end
		end
		-- set numGuarding to the counts made this evaluation frame
		for tID, num in pairs(numGuarding) do
			numGuarding[tID] = 0
		end
		for tID, num in pairs(guardingCount) do
--			Spring.Echo(tID, num)
			numGuarding[tID] = num
		end
	end
	
	if gf % 900 == 0 then
		baseXZ = getBaseXZ()
	end
	
end