-- All credit goes to justa.
ENT.Type 	= "anim"
ENT.Base 	= "base_anim"
ENT.Author 	= "justa"

-- AddCSLuaFile & resource.AddFile
AddCSLuaFile()

-- Server
if (SERVER) then
	function ENT:SetPositions(sPos, ePos)
		self.min = sPos 
		self.max = ePos
	end

	function ENT:Initialize()
		-- Basic setup for a zone-type entity
		local box = (self.max - self.min) * 2
		self:SetSolid(SOLID_BBOX)
		self:PhysicsInitBox(-box, box)
		self:SetCollisionBounds(self.min, self.max)
		self:SetTrigger(true)
		self:DrawShadow(false)
		self:SetNotSolid(true)
		self:SetNoDraw(true)

		-- Disable collisions
		self._obj_physics = self:GetPhysicsObject()
		if (self._obj_physics) and self._obj_physics:IsValid() then
			self._obj_physics:Sleep()
			self._obj_physics:EnableCollisions(false)
		end
	end

	function ENT:Touch(e)
	end

	function ENT:StartTouch(e)
		e.TouchingTrigger = true 
	end

	function ENT:EndTouch(e)
		OnPlayerTeleported(e)
		e.TouchingTrigger = false 
	end
end