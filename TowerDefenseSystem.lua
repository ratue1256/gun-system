-- Discord: e_z_1_o | Roblox: ezio25eziopro

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local TOWER_CONFIG = {
	Range = 40,
	FireRate = 0.6,
	Damage = 15,
	ProjectileSpeed = 90,
	RotationSpeed = 20,
	MaxPoolSize = 20,
}

local ProjectilePool = {}

local Projectile = {}
Projectile.__index = Projectile

function Projectile.new(template)
	local self = setmetatable({}, Projectile)
	self.Part = template:Clone()
	self.Active = false
	self.Part.Anchored = true
	self.Part.CanCollide = false
	self.Part.Parent = Workspace
	return self
end

function Projectile.GetFromPool(template)
	local proj = table.remove(ProjectilePool)
	if not proj then
		proj = Projectile.new(template)
	end
	proj.Active = true
	proj.Part.Transparency = 0
	return proj
end

function Projectile:ReturnToPool()
	self.Active = false
	self.Part.Transparency = 1
	self.Part.CFrame = CFrame.new(0, -500, 0)
	if #ProjectilePool < TOWER_CONFIG.MaxPoolSize then
		table.insert(ProjectilePool, self)
	else
		self.Part:Destroy()
	end
end

function Projectile:Launch(startPos, targetPart, speed, damage, onHit)
	local elapsed = 0
	local origin = startPos
	local initialDistance = (targetPart.Position - origin).Magnitude
	local traveled = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not self.Active or not targetPart or not targetPart.Parent then
			connection:Disconnect()
			self:ReturnToPool()
			return
		end

		elapsed += dt
		local targetPos = targetPart.Position
		local direction = (targetPos - origin).Unit
		local distanceThisFrame = speed * dt
		traveled += distanceThisFrame

		local newPos = self.Part.Position + direction * distanceThisFrame
		local arcOffset = math.sin(elapsed * math.pi) * 1.5
		self.Part.CFrame = CFrame.new(newPos + Vector3.new(0, arcOffset * dt, 0), targetPos)

		if (newPos - targetPos).Magnitude < 3 or traveled >= initialDistance then
			connection:Disconnect()
			onHit(damage, targetPart)
			self:ReturnToPool()
		end
	end)
end

local Tower = {}
Tower.__index = Tower

function Tower.new(model, config)
	local self = setmetatable({}, Tower)
	self.Model = model
	self.Head = model:WaitForChild("Head")
	self.MuzzlePoint = model:FindFirstChild("Muzzle") or self.Head
	self.Config = config
	self.CurrentTarget = nil
	self.LastFireTime = 0
	self.Connection = nil
	self.ProjectileTemplate = self:GetProjectileTemplate()
	return self
end

function Tower:GetProjectileTemplate()
	local existing = ReplicatedStorage:FindFirstChild("ProjectileTemplate")
	if existing then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "ProjectileTemplate"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.6, 0.6, 0.6)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 140, 0)
	part.Parent = ReplicatedStorage
	return part
end

function Tower:FindTarget()
	local closestTarget = nil
	local closestDistance = self.Config.Range

	for _, tagged in ipairs(CollectionService:GetTagged("Enemy")) do
		local head = tagged:FindFirstChild("Head")
		local humanoid = tagged:FindFirstChild("Humanoid")
		if head and humanoid and humanoid.Health > 0 and head.Transparency < 1 then
			local distance = (self.MuzzlePoint.Position - head.Position).Magnitude
			if distance <= closestDistance then
				closestDistance = distance
				closestTarget = head
			end
		end
	end

	return closestTarget
end

function Tower:RotateTowardsTarget(target, dt)
	local towerPos = self.Head.Position
	local targetPos = target.Position
	local direction = (targetPos - towerPos).Unit
	local goalCFrame = CFrame.new(towerPos, targetPos)

	local alpha = math.clamp(self.Config.RotationSpeed * dt, 0, 1)
	self.Head.CFrame = self.Head.CFrame:Lerp(goalCFrame, alpha)
end

function Tower:IsAimedAtTarget(target)
	return true
end

function Tower:OnProjectileHit(damage, targetPart)
	local character = targetPart.Parent
	local humanoid = character and character:FindFirstChild("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(damage)
		if humanoid.Health <= 0 then
			self.CurrentTarget = nil
			character:Destroy()
		end
	end
end

function Tower:Fire()
	local proj = Projectile.GetFromPool(self.ProjectileTemplate)
	proj.Part.CFrame = self.MuzzlePoint.CFrame
	proj:Launch(
		self.MuzzlePoint.Position,
		self.CurrentTarget,
		self.Config.ProjectileSpeed,
		self.Config.Damage,
		function(damage, targetPart)
			self:OnProjectileHit(damage, targetPart)
		end
	)
end

function Tower:Update(dt)
	if not self.CurrentTarget or not self.CurrentTarget.Parent then
		self.CurrentTarget = self:FindTarget()
	else
		local distance = (self.MuzzlePoint.Position - self.CurrentTarget.Position).Magnitude
		if distance > self.Config.Range then
			self.CurrentTarget = self:FindTarget()
		end
	end

	if self.CurrentTarget then
		self:RotateTowardsTarget(self.CurrentTarget, dt)

		local now = os.clock()
		if self:IsAimedAtTarget(self.CurrentTarget) and (now - self.LastFireTime) >= self.Config.FireRate then
			self.LastFireTime = now
			self:Fire()
		end
	end
end

function Tower:Start()
	self.Connection = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)
end

function Tower:Stop()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

local activeTowers = {}

local function InitializeTower(model)
	if not model:FindFirstChild("Head") then
		return
	end
	local tower = Tower.new(model, TOWER_CONFIG)
	tower:Start()
	table.insert(activeTowers, tower)
end

local towerFolder = Workspace:FindFirstChild("Towers") or Workspace
for _, model in ipairs(towerFolder:GetChildren()) do
	if model:IsA("Model") and CollectionService:HasTag(model, "Tower") then
		InitializeTower(model)
	end
end

CollectionService:GetInstanceAddedSignal("Tower"):Connect(function(model)
	if model:IsA("Model") then
		InitializeTower(model)
	end
end)

CollectionService:GetInstanceRemovedSignal("Tower"):Connect(function(model)
	for i, tower in ipairs(activeTowers) do
		if tower.Model == model then
			tower:Stop()
			table.remove(activeTowers, i)
			break
		end
	end
end)
