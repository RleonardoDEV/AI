class_name Terrain
extends RefCounted
## Terrain material table: ids, palette and per-material physical properties.
##
## The palette is the backbone of the art direction, so it lives in one place.
## Colours are slightly desaturated bases; per-cell noise variation and the
## terrain shader (light, water, wind, weather) add the richness on top.

enum T {
	DEEP_WATER,
	WATER,
	SHALLOW,
	SAND,
	DIRT,
	GRASS,
	LUSH,
	DRY,
	ROCK,
	SNOW,
	LAVA,
	ASH,
	MUD,
	ICE,
}

const COUNT: int = 14

## Base albedo per material.
const COLORS: PackedColorArray = [
	Color(0.055, 0.118, 0.219),   # DEEP_WATER
	Color(0.098, 0.263, 0.427),   # WATER
	Color(0.180, 0.482, 0.611),   # SHALLOW
	Color(0.839, 0.752, 0.533),   # SAND
	Color(0.392, 0.301, 0.219),   # DIRT
	Color(0.278, 0.525, 0.270),   # GRASS
	Color(0.164, 0.400, 0.223),   # LUSH
	Color(0.639, 0.588, 0.360),   # DRY
	Color(0.400, 0.392, 0.415),   # ROCK
	Color(0.878, 0.913, 0.945),   # SNOW
	Color(0.949, 0.388, 0.129),   # LAVA
	Color(0.203, 0.192, 0.223),   # ASH
	Color(0.286, 0.254, 0.180),   # MUD
	Color(0.698, 0.831, 0.878),   # ICE
]

## Shader material class, encoded into the data texture's alpha channel.
## Nearest-neighbour sampling preserves these exact quantised values.
const MAT_LAND: float = 0.0
const MAT_WATER: float = 0.25
const MAT_DEEP: float = 0.35
const MAT_LAVA: float = 0.50
const MAT_SNOW: float = 0.65
const MAT_ICE: float = 0.75
const MAT_ASH: float = 0.90

## Maximum vegetation a material can sustain.
const FERTILITY: PackedFloat32Array = [
	0.0, 0.0, 0.05, 0.10, 0.55, 1.00, 1.00, 0.45, 0.06, 0.02, 0.0, 0.30, 0.75, 0.0
]

## How readily a cell carries fire (0 = inert).
const FLAMMABILITY: PackedFloat32Array = [
	0.0, 0.0, 0.0, 0.05, 0.25, 0.85, 1.00, 0.95, 0.02, 0.0, 0.0, 0.10, 0.20, 0.0
]

## Movement cost multiplier for walkers.
const MOVE_COST: PackedFloat32Array = [
	3.0, 2.4, 1.5, 1.15, 1.0, 1.0, 1.1, 1.0, 1.45, 1.6, 4.0, 1.05, 1.6, 1.25
]

static func is_water(t: int) -> bool:
	return t <= T.SHALLOW

static func is_deep_water(t: int) -> bool:
	return t <= T.WATER

static func is_walkable(t: int) -> bool:
	return t > T.WATER and t != T.LAVA

static func is_solid_rock(t: int) -> bool:
	return t == T.ROCK

static func mat_flag(t: int) -> float:
	match t:
		T.DEEP_WATER:
			return MAT_DEEP
		T.WATER, T.SHALLOW:
			return MAT_WATER
		T.LAVA:
			return MAT_LAVA
		T.SNOW:
			return MAT_SNOW
		T.ICE:
			return MAT_ICE
		T.ASH:
			return MAT_ASH
	return MAT_LAND

static func color_of(t: int) -> Color:
	return COLORS[t]

static func name_of(t: int) -> String:
	return ["Deep Water", "Water", "Shallows", "Sand", "Dirt", "Grass", "Lush",
			"Dry Grass", "Rock", "Snow", "Lava", "Ash", "Mud", "Ice"][t]
