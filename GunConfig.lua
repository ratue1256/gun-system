
export type GunStats = {
	DisplayName: string,
	FireModes: { string },
	FireRate: number,
	BaseDamage: number,
	HeadshotMultiplier: number,
	MagSize: number,
	ReloadTime: number,
	MaxRange: number,
	FireSound: string,
	ReloadSound: string?,
	Spread: number?,
	RaysPerShot: number?,
	RayRadius: number?,
	MuzzleVelocity: number?,
	RecoilMin: { number }?,
	RecoilMax: { number }?,
}

local GunConfig = {}

GunConfig.Weapons = {
	M4A1 = {
		DisplayName = "M4A1 Carbine",
		FireModes = { "Auto", "Semi", "Safe" },
		FireRate = 750,
		BaseDamage = 30,
		HeadshotMultiplier = 3.0,
		MagSize = 30,
		ReloadTime = 2.2,
		MaxRange = 3000,
		FireSound = "rbxassetid://8169240213",
		ReloadSound = "rbxassetid://138089881272812",
		Spread = 1.5,
		RaysPerShot = 1,
		RayRadius = 0.5,
		MuzzleVelocity = 2500,
		RecoilMin = { 0.5, -0.2 },
		RecoilMax = { 1.2, 0.2 },
	} :: GunStats,

	Glock17 = {
		DisplayName = "Glock 17",
		FireModes = { "Semi", "Safe" },
		FireRate = 450,
		BaseDamage = 22,
		HeadshotMultiplier = 2.5,
		MagSize = 17,
		ReloadTime = 1.6,
		MaxRange = 1000,
		FireSound = "rbxassetid://6581933860",
		ReloadSound = "rbxassetid://115336502985781",
		Spread = 0.8,
		RaysPerShot = 1,
		RayRadius = 0.5,
		MuzzleVelocity = 1800,
		RecoilMin = { 0.5, -0.2 },
		RecoilMax = { 1.2, 0.2 },
	} :: GunStats,
}

return GunConfig
