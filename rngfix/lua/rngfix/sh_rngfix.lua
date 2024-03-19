-- All credit to justa
-- RNGFix

local lastGroundEnt = {}
local lastTickPredicted = {}
local lastBase = {}
local tick = {}
local btns = {}
local obtns = {}
local vels  = {}
local lastTeleport = {}
local teleportedSeq = {}
local lastCollision = {}
local lastLand = {}

NON_JUMP_VELOCITY = 140.0 
MIN_STANDABLE_ZNRM = 0.7	
LAND_HEIGHT = 2.0 

local unducked = Vector(16, 16, 62)
local ducked = Vector(16, 16, 45)
local duckdelta = (unducked.z / ducked.z) / 2

function ClipVelocity(vel, nrm)
	local backoff = vel:Dot(nrm)
	local out = Vector()
	out.x = vel.x - nrm.x * backoff 
	out.y = vel.y - nrm.y * backoff 
	out.z = vel.z - nrm.z * backoff 
	return out 
end

function PreventCollision(ply, origin, collision, veltick, mv)
	local no = collision - veltick 
	no.z = no.z + 0.1 

	lastTickPredicted[ply] = 0
	mv:SetOrigin(no)
end 

function CanJump(ply)
	if not btns[ply] or not obtns[ply] then return true end
	if btns[ply] and bit.band(btns[ply], IN_JUMP) == 0 then return false end 
	if obtns[ply] and bit.band(obtns[ply], IN_JUMP) != 0 then return false end 
	return true 
end 

function Duck(ply, origin, mins, max)
	local ducking = ply:Crouching()
	local nextducking = ducking 
	
	if not ducking and bit.band(btns[ply], IN_DUCK) != 0 then 
		origin.z = origin.z + duckdelta 
		nextducking = true 
	elseif bit.band(btns[ply], IN_DUCK) == 0 and ducking then 
		origin.z = origin.z - duckdelta 

		local tr = util.TraceHull{
			start = origin,
			endpos = origin,
			mins = Vector(-16.0, -16.0, 0.0),
			maxs = unducked,
			mask = MASK_PLAYERSOLID_BRUSHONLY,
			filter = ply
		}

		if tr.Hit then 
			origin.z = origin.z + duckdelta 
		else 
			nextducking = false 
		end 
	end 

	mins = Vector(-16.0, -16.0, 0.0) 
	max = nextducking and ducked or unducked 
	return origin, mins, max 
end 

function StartGravity(ply, velocity)
	local localGravity = ply:GetGravity()
	if localGravity == 0.0 then localGravity = 1.0 end

	local baseVelocity = ply:GetBaseVelocity()
	velocity.z = velocity.z + (baseVelocity.z - localGravity * 800 * 0.5) * FrameTime()

	-- baseVelocity.z would get cleared here but we shouldn't do that since this is just a prediction.
	return velocity
end

function FinishGravity(ply, velocity)
	local localGravity = ply:GetGravity()
	if localGravity == 0.0 then localGravity = 1.0 end

	velocity.z = velocity.z - localGravity * 800 * 0.5 * FrameTime()

	return velocity
end


local AA = 500
local MV = 32.8
function PredictVelocity(ply, mv, p)
	local a = mv:GetMoveAngles()
	local fw, r = a:Forward(), a:Right()
	local fmove, smove = mv:GetForwardSpeed(), mv:GetSideSpeed()
	local velocity =  mv:GetVelocity()

	if ply.Style == 2 then 
		fmove = mv:KeyDown(IN_FORWARD) and fmove + 500 or fmove 
		fmove = mv:KeyDown(IN_BACK) and fmove - 500 or fmove
	else 
		smove = mv:KeyDown(IN_MOVERIGHT) and smove + 500 or smove
		smove = mv:KeyDown(IN_MOVELEFT) and smove - 500 or smove
	end 

	fw.z, r.z = 0,0
	fw:Normalize()
	r:Normalize()

	local wish = fw * fmove + r * smove 
	wish.z = 0 

	local wishspd = wish:Length()
	local maxspeed = mv:GetMaxSpeed()
	if wishspd > maxspeed then
		wish = wish * (maxspeed / wishspd)
		wishspd = maxspeed
	end

	local wishspeed = math.Clamp(wishspd, 0, MV)
	local wishdir = wish:GetNormal()
	local current = velocity:Dot( wishdir )
	local addspeed = wishspeed - current

	if addspeed <= 0 then 
		return velocity 
	end 

	local acc = AA * FrameTime() * wishspd 
	if acc > addspeed then 
		acc = addspeed 
	end 

	return velocity + (wishdir * acc)
end 

function DoPreTickChecks(ply, mv, cmd)
	if not ply:Alive() then return false end 
	if not ply:GetMoveType() == MOVETYPE_WALK then return false end 
	if not ply:WaterLevel() == 0 then return false end 

	lastGroundEnt[ply] = ply:GetGroundEntity()

	if (not CanJump(ply)) and lastGroundEnt[ply] != NULL then return false end

	btns[ply] = mv:GetButtons()
	obtns[ply] = mv:GetOldButtons()
	lastTickPredicted[ply] = tick[ply] 

	local vel = PredictVelocity(ply, mv, false)
	--vel = StartGravity(ply, vel)

	local shouldDoDownhillFixInstead = false 

	local base = (bit.band(ply:GetFlags(), FL_BASEVELOCITY) != 0) and ply:GetBaseVelocity() or Vector(0, 0, 0)
	vel:Add(base)

	lastBase[ply] = base;
	vels[ply] = vel;
	
	local origin = mv:GetOrigin()
	local vMins = ply:OBBMins()
	local vMaxs = ply:OBBMaxs()
	local vEndPos = origin * 1
	vEndPos, vMins, vMaxs = Duck(ply, vEndPos, vMins, vMaxs)
	vEndPos = vEndPos + (vel * FrameTime())

	local tr = util.TraceHull{
		start = origin,
		endpos = vEndPos,
		mins = vMins,
		maxs = vMaxs,
		mask = MASK_PLAYERSOLID_BRUSHONLY,
		filter = ply
	}

	local nrm = tr.HitNormal 
	
	if tr.Hit and not tr.HitNonWorld then
		lastCollision[ply] = tick[ply]
		if ply:IsOnGround() then return false end 
		
		if nrm.z < MIN_STANDABLE_ZNRM then return end 
		if vel.z > NON_JUMP_VELOCITY then return end 

		local collision = tr.HitPos
		local veltick = vel * FrameTime()
		
		// Slopefix
		if (nrm.z < 1.0 and nrm.x * vel.x + nrm.y * vel.y < 0.0) then 
			local newvel = ClipVelocity(vel, nrm)

			if (newvel.x * newvel.x + newvel.y * newvel.y > vel.x * vel.x + vel.y * vel.y) then 
				shouldDoDownhillFixInstead = true;
			end 

			if not shouldDoDownhillFixInstead then 
				PreventCollision(ply, origin, collision, veltick, mv)
				return
			end
		end 

		// Edgebug fix
		local edgebug = true 

		if (edgebug) then 
			local fraction_left = 1 - tr.Fraction 
			local tickEnd = Vector()

			if (nrm.z == 1) then 
				tickEnd.x = collision.x + veltick.x * fraction_left
				tickEnd.y = collision.y + veltick.y * fraction_left
				tickEnd.z = collision.z
			else 
				local velocity2 = ClipVelocity(vel, nrm)

				if (velocity2.z > NON_JUMP_VELOCITY) then 
					return 
				else 
					velocity2 = velocity2 * FrameTime() * fraction_left
					tickEnd = collision + velocity2
				end 
			end

			local tickEndBelow = Vector()
			tickEndBelow.x = tickEnd.x
			tickEndBelow.y = tickEnd.y
			tickEndBelow.z = tickEnd.z - LAND_HEIGHT;

			local tr_edge = util.TraceHull{
				start = tickEnd,
				endpos = tickEndBelow,
				mins = vMins,
				maxs = vMaxs,
				mask = MASK_PLAYERSOLID,
				filter = ply
			}

			if (tr_edge.Hit) then 
				if (tr_edge.HitNormal.z >= MIN_STANDABLE_ZNRM) then return end 
				if TracePlayerBBoxForGround(tickEnd, tickEndBelow, vMins, vMaxs, ply) then return end
			end 
			
			PreventCollision(ply, origin, collision, veltick, mv)
		end 
	end 
end 

function OnPlayerHitGround(ply, inWater, float, speed)
	if inWater or float then return end
	lastLand[ply] = tick[ply]
end 
hook.Add("OnPlayerHitGround", "RNGFIXGround", OnPlayerHitGround)

function DoInclineCollisonFixes(ply, mv, nrm) 
	if not ply:IsOnGround() then return end  
	if not CanJump(ply) then return end 
	if not vels[ply] then return end 
	if (tick[ply] != lastTickPredicted[ply]) then return end 
	
	local velocity = vels[ply]
	local dot = nrm.x * velocity.x + nrm.x * velocity.z
	local newVelocity = ClipVelocity(velocity, nrm)
	local downhill = (newVelocity.x * newVelocity.x + newVelocity.y * newVelocity.y  > velocity.x*velocity.x + velocity.y*velocity.y)
	
	if not downhill then 
		return 
	end 

	newVelocity.z = 0 
	mv:SetVelocity(newVelocity)
end 

function OnPlayerTeleported(activator)
	local isWorthIt = (activator:GetVelocity():Length2D()/vels[activator]:Length2D())<0.4
	if (not isWorthIt) then return end 

	if (lastTeleport[activator] == tick[activator]-1) then
		teleportedSeq[activator] = true
	end

	lastTeleport[activator] = tick[activator]
end 

function DoTelehopFix(ply, mv)
	if CLIENT then
	elseif SERVER then 
	end
	if ply.TouchingTrigger then 
		OnPlayerTeleported(ply)
	end 

	if not ply:Alive() then return false end 
	if not ply:GetMoveType() == MOVETYPE_WALK then return false end 
	if not ply:WaterLevel() == 0 then return false end 

	if (tick[ply] != lastTickPredicted[ply]) then return end 
	if lastTeleport[ply] ~= tick[ply] then return end
	if teleportedSeq[ply] then return end
	if not (lastCollision[ply] == tick[ply] or lastLand[ply] == tick[ply]) then return end
	local vel = vels[ply]	
	if vel then 
		if (ply:IsOnGround()) then 
			vel.z = 0 
		end 

		mv:SetVelocity(vel)
	end 
end 

function CheckTick(e)
	return tick[e]
end 

hook.Add("SetupMove", "RNGFix", function(ply, mv, cmd)
	if not tick[ply] then 
		tick[ply] = 0
	end 

	DoTelehopFix(ply,mv)

	tick[ply] = tick[ply] + 1 
	teleportedSeq[ply] = false 

	DoPreTickChecks(ply, mv, cmd)
end )

function PlayerPostThink(ply, mv)
	if not ply:Alive() then return end 
	if not ply:GetMoveType() == MOVETYPE_WALK then return end 
	if ply:WaterLevel() ~= 0 then return end 

	local origin = mv:GetOrigin()
	local vMins = ply:OBBMins()
	local vMaxs = ply:OBBMaxs()
	local vEndPos = origin * 1
	vEndPos.z = vEndPos.z - vMaxs.z

	local tr = util.TraceHull{
		start = origin,
		endpos = vEndPos,
		mins = vMins,
		maxs = vMaxs,
		mask = MASK_PLAYERSOLID,
		filter = ply
	}

	if tr.Hit then 
		local nrm = tr.HitNormal

		if nrm.z > MIN_STANDABLE_ZNRM and nrm.z < 1 then 
			DoInclineCollisonFixes(ply, mv, nrm)
		end 
	end 

	if SERVER then 
		--DoTelehopFix(ply, mv)
	end 
end 
hook.Add("FinishMove", "RNGFixPost", PlayerPostThink)

function TracePlayerBBoxForGround(origin, originBelow, mins, maxs, ply)
	local origMins, origMaxs = Vector(mins), Vector(maxs)
	local tr = nil

	mins = origMins
	maxs = Vector(math.min(origMaxs.x, 0.0), math.min(origMaxs.y, 0.0), origMaxs.z)
	tr = util.TraceHull({
		start = origin,
		endpos = originBelow,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID_BRUSHONLY,
	})
	if tr.Hit and tr.HitNormal.z >= MIN_STANDABLE_ZNRM then
		return tr
	end

	mins = Vector(math.max(origMins.x, 0.0), math.max(origMins.y, 0.0), origMins.z)
	maxs = origMaxs
	tr = util.TraceHull({
		start = origin,
		endpos = originBelow,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID_BRUSHONLY
	})
	if tr.Hit and tr.HitNormal.z >= MIN_STANDABLE_ZNRM then
		return tr
	end

	mins = Vector(origMins.x, math.max(origMins.y, 0.0), origMins.z)
	maxs = Vector(math.min(origMaxs.x, 0.0), origMaxs.y, origMaxs.z)
	tr = util.TraceHull({
		start = origin,
		endpos = originBelow,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID_BRUSHONLY
	})
	if tr.Hit and tr.HitNormal.z >= MIN_STANDABLE_ZNRM then
		return tr
	end

	mins = Vector(math.max(origMins.x, 0.0), origMins.y, origMins.z)
	maxs = Vector(origMaxs.x, math.min(origMaxs.y, 0.0), origMaxs.z)
	tr = util.TraceHull({
		start = origin,
		endpos = originBelow,
		mins = mins,
		maxs = maxs,
		mask = MASK_PLAYERSOLID_BRUSHONLY
	})
	if tr.Hit and tr.HitNormal.z >= MIN_STANDABLE_ZNRM then
		return tr
	end

	return nil
end

if SERVER then 
	hook.Add("InitPostEntity", "RNGFIXtele", function()
		for _, ent in pairs( ents.FindByClass("trigger_teleport") ) do
			local pos = ent:GetPos()
			local mins, maxs = ent:GetCollisionBounds()

			local trigger = ents.Create("ent_trigger")
			trigger:SetPos(pos)
			trigger:SetPositions(mins, maxs)
			trigger:Spawn()
		end
	end)
end