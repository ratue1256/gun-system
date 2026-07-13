local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local SpatialAudioService = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local MAX_CONCURRENT_SOUNDS = 4
local activeSoundCount = 0

local function lerpNum(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function estimateRoom(origin: Vector3): (number, number)
	local directions = {
		Vector3.new(0, 1, 0), Vector3.new(0, -1, 0),
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)
	}
	local distances = {}
	local absorptionSum = 0
	local totalArea = 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end
	for _, dir in pairs(directions) do
		local res = Workspace:Raycast(origin, dir * 120, params)
		local dist = res and res.Distance or 120
		table.insert(distances, dist)
		local mat = res and res.Material or Enum.Material.Plastic
		local coef = 0.25
		if mat == Enum.Material.Concrete or mat == Enum.Material.Metal or mat == Enum.Material.DiamondPlate then
			coef = 0.08
		elseif mat == Enum.Material.Fabric or mat == Enum.Material.Grass or mat == Enum.Material.Sand or mat == Enum.Material.Snow then
			coef = 0.70
		elseif mat == Enum.Material.Wood or mat == Enum.Material.WoodPlanks then
			coef = 0.30
		elseif mat == Enum.Material.Glass then
			coef = 0.05
		end
		local area = dist * dist
		absorptionSum += area * coef
		totalArea += area
	end
	local lx = distances[3] + distances[4]
	local ly = distances[1] + distances[2]
	local lz = distances[5] + distances[6]
	local volume = lx * ly * lz
	local rt60 = 0.161 * volume / math.max(absorptionSum, 1)
	local avgAbsorption = absorptionSum / math.max(totalArea, 1)
	return math.clamp(rt60, 0.05, 2.0), volume
end

local function calculateWallThickness(origin: Vector3, target: Vector3, firstHit: RaycastResult): number
	local wall = firstHit.Instance
	local direction = (target - origin).Unit
	local maxPenetration = 12
	local exitOrigin = firstHit.Position + direction * maxPenetration
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { wall }
	local exitHit = Workspace:Raycast(exitOrigin, -direction * (maxPenetration + 1), params)
	if exitHit then
		return (firstHit.Position - exitHit.Position).Magnitude
	end
	return 0
end

function SpatialAudioService.play(soundId: string, origin: Vector3)
	local camPos = camera.CFrame.Position
	local distance = (origin - camPos).Magnitude
	local delayTime = distance / 1100

	task.delay(delayTime, function()
		local volumeScale = 1
		if activeSoundCount >= MAX_CONCURRENT_SOUNDS then
			volumeScale = 0.25
		elseif activeSoundCount >= MAX_CONCURRENT_SOUNDS - 1 then
			volumeScale = 0.55
		end
		activeSoundCount += 1

		local attach = Instance.new("Attachment")
		attach.Position = origin
		attach.Parent = Workspace.Terrain

		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Volume = 0.5 * volumeScale
		sound.RollOffMinDistance = 10
		sound.RollOffMaxDistance = 350
		sound.RollOffMode = Enum.RollOffMode.Inverse
		sound.Parent = attach

		local eq = Instance.new("EqualizerSoundEffect")
		eq.HighGain = 0
		eq.MidGain = 0
		eq.LowGain = 0
		eq.Parent = sound

		local reverb = Instance.new("ReverbSoundEffect")
		reverb.DryLevel = -1.5
		reverb.WetLevel = -80
		reverb.DecayTime = 0.3
		reverb.Density = 0.2
		reverb.Diffusion = 0.3
		reverb.Parent = sound

		local rt60, roomVolume = estimateRoom(origin)
		local isIndoor = roomVolume < 80000

		if isIndoor then
			if roomVolume < 15000 then
				reverb.DecayTime = math.clamp(rt60, 0.2, 0.8)
				reverb.Density = 0.4
				reverb.Diffusion = 0.5
				reverb.WetLevel = -22
			elseif roomVolume < 50000 then
				reverb.DecayTime = math.clamp(rt60, 0.3, 1.2)
				reverb.Density = 0.55
				reverb.Diffusion = 0.65
				reverb.WetLevel = -16
			else
				reverb.DecayTime = math.clamp(rt60, 0.4, 1.6)
				reverb.Density = 0.7
				reverb.Diffusion = 0.8
				reverb.WetLevel = -11
			end
		else
			reverb.DecayTime = 0.2
			reverb.Density = 0.15
			reverb.Diffusion = 0.2
			reverb.WetLevel = -35
		end

		sound:Play()

		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function(dt)
			if not sound or not sound.IsPlaying then
				connection:Disconnect()
				attach:Destroy()
				activeSoundCount = math.max(0, activeSoundCount - 1)
				return
			end

			local currentCamPos = camera.CFrame.Position
			local currentDist = (sound.Parent and (sound.Parent :: Attachment).Position - currentCamPos or Vector3.zero).Magnitude

			local airDampHigh = -math.clamp(currentDist * 0.025, 0, 10)
			local airDampMid = -math.clamp(currentDist * 0.012, 0, 6)
			local targetVol = 0.5 * volumeScale * math.clamp(1 - currentDist / 400, 0.1, 1)

			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			if player.Character then
				params.FilterDescendantsInstances = { player.Character }
			end

			local occ = Workspace:Raycast(origin, currentCamPos - origin, params)
			if occ and occ.Instance and occ.Instance.CanCollide then
				local thickness = calculateWallThickness(origin, currentCamPos, occ)
				local wallMat = occ.Material
				local absorptionCoef = 0.45
				if wallMat == Enum.Material.Metal or wallMat == Enum.Material.DiamondPlate then
					absorptionCoef = 0.75
				elseif wallMat == Enum.Material.Wood or wallMat == Enum.Material.WoodPlanks then
					absorptionCoef = 0.25
				elseif wallMat == Enum.Material.Concrete or wallMat == Enum.Material.Brick then
					absorptionCoef = 0.55
				end
				local loss = thickness * absorptionCoef
				airDampHigh -= (12 + loss * 2)
				airDampMid -= (5 + loss)
				targetVol = math.clamp((0.5 - thickness * 0.03) * volumeScale, 0.03, 0.5)
			end

			local smooth = 1 - math.exp(-dt * 5)
			sound.Volume = lerpNum(sound.Volume, targetVol, smooth)
			eq.HighGain = lerpNum(eq.HighGain, math.clamp(airDampHigh, -50, 0), smooth)
			eq.MidGain = lerpNum(eq.MidGain, math.clamp(airDampMid, -30, 0), smooth)
			eq.LowGain = lerpNum(eq.LowGain, math.clamp(-math.clamp(currentDist * 0.005, 0, 3), -10, 0), smooth)
		end)

		Debris:AddItem(attach, sound.TimeLength > 0 and sound.TimeLength + 1 or 5)
	end)
end

return SpatialAudioService
