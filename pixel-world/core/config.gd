class_name GameConfig
extends Node
## Tunable constants + persisted user settings.
##
## Anything a designer would want to tweak lives here, not scattered through
## the systems. Runtime-mutable preferences are persisted to user://settings.cfg

# --------------------------------------------------------------------------
# World
# --------------------------------------------------------------------------
const WORLD_W: int = 256
const WORLD_H: int = 256
const CELL_COUNT: int = WORLD_W * WORLD_H

## Sea level in normalised elevation space [0,1].
const SEA_LEVEL: float = 0.42
const BEACH_LEVEL: float = 0.46
const ROCK_LEVEL: float = 0.74
const SNOW_LEVEL: float = 0.86

# --------------------------------------------------------------------------
# Simulation timing
# --------------------------------------------------------------------------
## Seconds of simulated time per fixed tick.
const TICK_DT: float = 0.05
## Ticks per simulated day.
const TICKS_PER_DAY: int = 1200
## Simulated days per year.
const DAYS_PER_YEAR: int = 8
## Hard cap on ticks executed in a single frame (keeps frame time bounded).
const MAX_TICKS_PER_FRAME: int = 14

const SPEEDS: PackedFloat32Array = [0.0, 1.0, 2.0, 5.0, 10.0, 50.0, 100.0]
const SPEED_LABELS: PackedStringArray = ["II", "1X", "2X", "5X", "10X", "50X", "100X"]

# --------------------------------------------------------------------------
# Population
# --------------------------------------------------------------------------
const MAX_CREATURES: int = 520
const SOFT_POP_CAP: int = 420
const START_CREATURES: int = 260
const MAX_TREES: int = 1400
const MAX_PARTICLES: int = 1200
const MAX_SPECIES_SLOTS: int = 32

# --------------------------------------------------------------------------
# Spatial partitioning
# --------------------------------------------------------------------------
const GRID_CELL: int = 8

# --------------------------------------------------------------------------
# Sprite scale
# --------------------------------------------------------------------------
## How many sprite texels map onto one world cell. The terrain is always one
## texel per cell (perfectly pixel-aligned); creature and flora sprites are
## drawn at this ratio so a 16-texel tile covers ~3.2 cells, which keeps
## bodies readable at close zoom without swamping the map at range.
const SPRITE_TEXELS_PER_CELL: float = 5.0

# --------------------------------------------------------------------------
# Camera
# --------------------------------------------------------------------------
const ZOOM_MIN: float = 2.6
const ZOOM_MAX: float = 18.0
const ZOOM_DEFAULT: float = 4.0

# --------------------------------------------------------------------------
# Ecology balance
# --------------------------------------------------------------------------
const VEG_MAX: float = 1.0
const VEG_REGROW: float = 0.0165
const FIRE_SPREAD_BASE: float = 0.14
const FIRE_FUEL_BURN: float = 0.55
const WATER_EVAPORATION: float = 0.004

# --------------------------------------------------------------------------
# Runtime settings (persisted)
# --------------------------------------------------------------------------
var show_minimap: bool = true
var show_debug: bool = false
var particles_enabled: bool = true
var weather_fx_enabled: bool = true
var show_creature_names: bool = false
var audio_enabled: bool = true

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	load_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "show_minimap", show_minimap)
	cfg.set_value("ui", "show_debug", show_debug)
	cfg.set_value("fx", "particles", particles_enabled)
	cfg.set_value("fx", "weather", weather_fx_enabled)
	cfg.set_value("audio", "enabled", audio_enabled)
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	show_minimap = cfg.get_value("ui", "show_minimap", true)
	show_debug = cfg.get_value("ui", "show_debug", false)
	particles_enabled = cfg.get_value("fx", "particles", true)
	weather_fx_enabled = cfg.get_value("fx", "weather", true)
	audio_enabled = cfg.get_value("audio", "enabled", true)
