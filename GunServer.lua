--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GunConfig = require(Shared:WaitForChild("GunConfig"))
local GunEvent = Remotes:WaitForChild("GunEvent") :: RemoteEvent

local equippedWeapons = {} :: { [Player]: { name: string, tool: Tool, lastFire: number } }
local playerPitch = {} :: { [Player]: number }

local HEAD_ACCESSORY_TYPES = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

local HEAD_ATTACHMENT_NAMES = {
	HatAttachment = true,
	HairAttachment = true,
	FaceFrontAttachment = true,
	FaceCenterAttachment = true,
}

local HEAD_KEYWORDS = { "helmet", "helm", "casque", "hair", "cheveux", "hat", "chapeau", "mask", "masque", "hood", "capuche", "aura" }

local function containsAny(text: string, keywords: {string}): boolean
	for _, kw in pairs(keywords) do
		if text:find(kw, 1, true) then return true end
	end
	return false
end

local function isHeadAccessoryInstance(accessory: Accessory): boolean
	local accType = accessory.AccessoryType
	if accType and accType ~= Enum.AccessoryType.Unknown then
		return HEAD_ACCESSORY_TYPES[accType] == true
	end
	for _, descendant in pairs(accessory:GetDescendants()) do
		if descendant:IsA("Attachment") and HEAD_ATTACHMENT_NAMES[descendant.Name] then
			return true
		end
	end
	return containsAny(accessory.Name:lower(), HEAD_KEYWORDS)
end

local function isHeadPart(hitPart: Instance): boolean
	if not hitPart then return false end
	local part = hitPart
	if part:IsA("Decal") or part:IsA("Texture") then
		part = part.Parent
		if not part then return false end
	end
	if part.Name == "Head" then return true end
	local ancestor = part.Parent
	local depth = 0
	while ancestor and depth < 4 do
		depth += 1
		if ancestor:IsA("Accessory") then
			return isHeadAccessoryInstance(ancestor)
		elseif ancestor:IsA("Model") and containsAny(ancestor.Name:lower(), HEAD_KEYWORDS) then
			return true
		end
		if ancestor:FindFirstChildOfClass("Humanoid") then break end
		ancestor = ancestor.Parent
	end
	return false
end

local function getCharacterFromPart(part: Instance): Model?
	local ancestor = part
	while ancestor do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function validateHit(firer: Player, weaponName: string, hitPart: Instance, hitPos: Vector3, origin: Vector3): boolean
	local stats = GunConfig.Weapons[weaponName]
	if not stats then return false end
	local data = equippedWeapons[firer]
	if not data or data.name ~= weaponName then return false end
	if not data.tool or data.tool.Parent ~= firer.Character then return false end
	if (hitPos - origin).Magnitude > stats.MaxRange + 10 then return false end
	local char = getCharacterFromPart(hitPart)
	if char == firer.Character then return false end
	return true
end

local function replicateShoot(firer: Player, weaponName: string, origin: Vector3, direction: Vector3)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= firer then
			GunEvent:FireClient(p, "ReplicateShoot", weaponName, origin, direction)
		end
	end
end

local function replicateHitEffect(position: Vector3, normal: Vector3, part: Instance, color: Color3, material: Enum.Material)
	for _, p in ipairs(Players:GetPlayers()) do
		GunEvent:FireClient(p, "ReplicateHitEffect", position, normal, part, color, material)
	end
end

local function onHit(firer: Player, weaponName: string, hitPart: Instance, hitPos: Vector3, hitNorm: Vector3, origin: Vector3, _direction: Vector3, color: Color3, material: Enum.Material)
	if not validateHit(firer, weaponName, hitPart, hitPos, origin) then return end
	local stats = GunConfig.Weapons[weaponName]
	local targetChar = getCharacterFromPart(hitPart)
	local isHeadshot = isHeadPart(hitPart)
	local baseDamage = stats.Damage or 25
	local headshotMult = stats.HeadshotMultiplier or 2
	local finalDamage = isHeadshot and math.floor(baseDamage * headshotMult) or baseDamage

	if targetChar then
		local hum = targetChar:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health -= finalDamage
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer then
				GunEvent:FireClient(firer, "HitFeedback", isHeadshot and "Headshot" or "Hit", finalDamage, hitPos)
				GunEvent:FireClient(targetPlayer, "HitFeedback", isHeadshot and "Headshot" or "Hit", finalDamage, hitPos)
			end
		end
	end
	replicateHitEffect(hitPos, hitNorm, hitPart, color, material)
end

local function onShoot(firer: Player, weaponName: string, origin: Vector3, direction: Vector3)
	local stats = GunConfig.Weapons[weaponName]
	if not stats then return end
	local data = equippedWeapons[firer]
	if not data or data.name ~= weaponName then return end
	local now = os.clock()
	local interval = 60 / stats.FireRate
	if now - data.lastFire < interval then return end
	data.lastFire = now
	replicateShoot(firer, weaponName, origin, direction)
end

GunEvent.OnServerEvent:Connect(function(player: Player, action: string, ...: any)
	local args = {...}
	if action == "Equip" then
		local name = tostring(args[1])
		local tool = args[2] :: Tool
		if GunConfig.Weapons[name] and tool and tool.Parent == player.Character then
			equippedWeapons[player] = { name = name, tool = tool, lastFire = 0 }
		end
	elseif action == "Unequip" then
		equippedWeapons[player] = nil
	elseif action == "UpdatePitch" then
		local pitch = tonumber(args[1]) or 0
		playerPitch[player] = pitch
		local char = player.Character
		if char then char:SetAttribute("LookPitch", pitch) end
	elseif action == "Shoot" then
		local weaponName = tostring(args[1])
		local origin = args[2] :: Vector3
		local direction = args[3] :: Vector3
		onShoot(player, weaponName, origin, direction)
	elseif action == "Hit" then
		local weaponName = tostring(args[1])
		local hitPart = args[2] :: Instance
		local hitPos = args[3] :: Vector3
		local hitNorm = args[4] :: Vector3
		local origin = args[5] :: Vector3
		local direction = args[6] :: Vector3
		local color = args[7] :: Color3
		local material = args[8] :: Enum.Material
		onHit(player, weaponName, hitPart, hitPos, hitNorm, origin, direction, color, material)
	end
end)

Players.PlayerRemoving:Connect(function(p)
	equippedWeapons[p] = nil
	playerPitch[p] = nil
end)

print("GunServer loaded.")
