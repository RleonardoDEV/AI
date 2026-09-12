class_name Biome
extends RefCounted
## Biome classification from the elevation / moisture / temperature triple,
## plus the presentation data each biome contributes (label, flora density).

enum B {
	DEEP_OCEAN, OCEAN, REEF, BEACH, GRASSLAND, FOREST, RAINFOREST,
	SAVANNA, DESERT, TUNDRA, GLACIER, MOUNTAIN, SWAMP, VOLCANIC,
}

const COUNT: int = 14

const NAMES: PackedStringArray = [
	"Deep Ocean", "Ocean", "Reef", "Beach", "Grassland", "Forest", "Rainforest",
	"Savanna", "Desert", "Tundra", "Glacier", "Mountain", "Swamp", "Volcanic",
]

## Tree density per biome (probability weight used when scattering flora).
const TREE_DENSITY: PackedFloat32Array = [
	0.0, 0.0, 0.0, 0.004, 0.02, 0.20, 0.30, 0.035, 0.004, 0.012, 0.0, 0.02, 0.09, 0.0
]

## Shrub / flower density per biome.
const SHRUB_DENSITY: PackedFloat32Array = [
	0.0, 0.0, 0.0, 0.01, 0.07, 0.06, 0.09, 0.06, 0.012, 0.03, 0.0, 0.02, 0.07, 0.005
]

## Classifies one cell. `elev`, `moist` in [0,1]; `temp` in degrees Celsius.
static func classify(elev: float, moist: float, temp: float) -> int:
	if elev < GameConfig.SEA_LEVEL - 0.10:
		return B.DEEP_OCEAN
	if elev < GameConfig.SEA_LEVEL - 0.02:
		return B.OCEAN
	if elev < GameConfig.SEA_LEVEL:
		return B.REEF if temp > 18.0 else B.OCEAN
	if elev < GameConfig.BEACH_LEVEL:
		return B.BEACH
	if elev > GameConfig.SNOW_LEVEL:
		return B.GLACIER if temp < -4.0 else B.MOUNTAIN
	if elev > GameConfig.ROCK_LEVEL:
		return B.MOUNTAIN
	# Lowland / midland climate table
	if temp < -2.0:
		return B.GLACIER if moist > 0.55 else B.TUNDRA
	if temp < 6.0:
		return B.TUNDRA if moist < 0.55 else B.FOREST
	if temp > 29.0:
		if moist < 0.26:
			return B.DESERT
		if moist < 0.55:
			return B.SAVANNA
		return B.RAINFOREST
	if moist < 0.22:
		return B.DESERT
	if moist < 0.40:
		return B.SAVANNA
	if moist < 0.62:
		return B.GRASSLAND
	if moist < 0.82:
		return B.FOREST
	return B.SWAMP if elev < GameConfig.BEACH_LEVEL + 0.06 else B.RAINFOREST

## Maps a biome (plus local detail noise) to a terrain material.
static func terrain_for(biome: int, elev: float, moist: float, temp: float, detail: float) -> int:
	match biome:
		B.DEEP_OCEAN:
			return Terrain.T.DEEP_WATER
		B.OCEAN:
			return Terrain.T.WATER
		B.REEF:
			return Terrain.T.SHALLOW
		B.BEACH:
			return Terrain.T.SAND
		B.GRASSLAND:
			return Terrain.T.GRASS if detail > -0.35 else Terrain.T.DRY
		B.FOREST:
			return Terrain.T.LUSH if detail > 0.0 else Terrain.T.GRASS
		B.RAINFOREST:
			return Terrain.T.LUSH
		B.SAVANNA:
			return Terrain.T.DRY if detail > -0.25 else Terrain.T.GRASS
		B.DESERT:
			return Terrain.T.SAND if detail > -0.5 else Terrain.T.DIRT
		B.TUNDRA:
			return Terrain.T.DIRT if detail > 0.15 else Terrain.T.DRY
		B.GLACIER:
			return Terrain.T.SNOW if detail > -0.4 else Terrain.T.ICE
		B.MOUNTAIN:
			if elev > GameConfig.SNOW_LEVEL and temp < 8.0:
				return Terrain.T.SNOW
			return Terrain.T.ROCK if detail > -0.45 else Terrain.T.DIRT
		B.SWAMP:
			return Terrain.T.MUD if detail > -0.1 else Terrain.T.SHALLOW
		B.VOLCANIC:
			return Terrain.T.ASH if detail > -0.6 else Terrain.T.LAVA
	return Terrain.T.DIRT
