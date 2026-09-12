class_name Creature
extends RefCounted
## A single animal: state, needs, phenotype and memory.
##
## Creatures are pooled objects updated on a stride (see SimContext.stride), so
## the per-tick cost stays flat as the simulation speed rises. Phenotype values
## are derived from DNA once at birth and cached as plain floats — the hot loop
## never indexes the genome.

enum State { WANDER, SEEK_FOOD, EAT, SEEK_WATER, DRINK, HUNT, FLEE, MATE, REST, MIGRATE, FLEE_FIRE }
enum Cause { STARVATION, DEHYDRATION, OLD_AGE, PREDATION, FIRE, DROWNING, COLD, HEAT, DIVINE }

const STATE_NAMES: PackedStringArray = [
	"Wandering", "Foraging", "Eating", "Thirsty", "Drinking", "Hunting",
	"Fleeing", "Courting", "Resting", "Migrating", "Panicking",
]
## Updates between full neighbour scans / resource searches.
const SCAN_EVERY: int = 3
const SEARCH_EVERY: int = 6

const CAUSE_NAMES: PackedStringArray = [
	"starvation", "dehydration", "old age", "predation", "fire", "drowning",
	"cold", "heat", "divine intervention",
]

# --- Identity -------------------------------------------------------------
var id: int = -1
var alive: bool = false
var species_id: int = 0
var species: Species = null
var dna: PackedFloat32Array = PackedFloat32Array()
var generation: int = 1
var birth_tick: int = 0

# --- Kinematics -----------------------------------------------------------
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
var facing: int = 0
var anim_t: float = 0.0

# --- Vitals ---------------------------------------------------------------
var age: float = 0.0            # simulated days
var health: float = 1.0
var energy: float = 0.8
var hunger: float = 0.2
var thirst: float = 0.2
var repro_drive: float = 0.0
var fear: float = 0.0

# --- Behaviour ------------------------------------------------------------
var state: int = State.WANDER
var state_timer: float = 0.0
var target_pos: Vector2 = Vector2.ZERO
var target_id: int = -1
var wander_phase: float = 0.0
## Perception is scheduled per *update*, not per simulated second: at 100x a
## single update covers seconds of world time, so a time-based cooldown would
## fire every update and searching would dominate the frame.
var scan_countdown: int = 0
var search_countdown: int = 0
var attack_cooldown: float = 0.0
var breed_cooldown: float = 0.0

# --- Memory ---------------------------------------------------------------
var mem_water: Vector2 = Vector2(-1, -1)
var mem_food: Vector2 = Vector2(-1, -1)
var mem_threat: Vector2 = Vector2(-1, -1)
var mem_threat_age: float = 999.0
var mem_fire: Vector2 = Vector2(-1, -1)
var mem_home: Vector2 = Vector2.ZERO

# --- Cached phenotype -----------------------------------------------------
var max_speed: float = 1.0
var vision: float = 8.0
var body_size: float = 1.0
var metabolism: float = 1.0
var lifespan: float = 20.0
var diet: float = 0.0
var temp_pref: float = 20.0
var social: float = 0.5
var fear_gene: float = 0.5
var stamina: float = 1.0
var aquatic: float = 0.0
var fertility: float = 0.5
var aggression: float = 0.0
var color: Color = Color.WHITE
var sprite_slot: int = 0
var lod: int = 1                 # extra stride multiplier when off-screen

func configure(sp: Species, genome: PackedFloat32Array, at: Vector2,
		gen: int, tick: int, rng: RandomNumberGenerator) -> void:
	species = sp
	species_id = sp.id
	sprite_slot = sp.sprite_slot
	dna = genome
	generation = gen
	birth_tick = tick
	pos = at
	mem_home = at
	vel = Vector2.from_angle(rng.randf() * TAU) * 0.2
	alive = true
	age = 0.0
	health = 1.0
	energy = rng.randf_range(0.62, 0.9)
	hunger = rng.randf_range(0.1, 0.35)
	thirst = rng.randf_range(0.1, 0.35)
	repro_drive = 0.0
	fear = 0.0
	state = State.WANDER
	state_timer = 0.0
	target_id = -1
	wander_phase = rng.randf() * TAU
	search_countdown = rng.randi_range(0, SEARCH_EVERY)
	scan_countdown = rng.randi_range(0, SCAN_EVERY)
	attack_cooldown = 0.0
	breed_cooldown = 2.0
	mem_water = Vector2(-1, -1)
	mem_food = Vector2(-1, -1)
	mem_threat = Vector2(-1, -1)
	mem_threat_age = 999.0
	mem_fire = Vector2(-1, -1)
	lod = 1
	_derive_phenotype()

func _derive_phenotype() -> void:
	var G := DNA.G
	max_speed = dna[G.SPEED] * 5.2 + 0.7
	vision = dna[G.VISION]
	body_size = dna[G.SIZE]
	metabolism = dna[G.METABOLISM]
	lifespan = dna[G.LIFESPAN]
	diet = dna[G.DIET]
	temp_pref = dna[G.TEMP_PREF]
	social = dna[G.SOCIAL]
	fear_gene = dna[G.FEAR]
	stamina = dna[G.STAMINA]
	aquatic = dna[G.AQUATIC]
	fertility = dna[G.FERTILITY]
	aggression = dna[G.AGGRESSION]
	color = DNA.color_of(dna)

# --------------------------------------------------------------------------
# Derived helpers
# --------------------------------------------------------------------------
func is_carnivore() -> bool:
	return diet > 0.62

func is_herbivore() -> bool:
	return diet < 0.38

func maturity() -> float:
	return lifespan * 0.11

func is_adult() -> bool:
	return age >= maturity()

## Visual scale in world cells (a newborn is visibly smaller).
func draw_scale() -> float:
	var growth: float = clampf(age / maxf(0.01, maturity()), 0.35, 1.0)
	return (0.52 + body_size * 0.38) * growth

func bite_power() -> float:
	return (0.18 + body_size * 0.55) * (0.35 + aggression) * clampf(health, 0.2, 1.0)

func meat_value() -> float:
	return 0.5 + body_size * 1.1

func state_name() -> String:
	return STATE_NAMES[state]

func age_label() -> String:
	return "%.1f / %.0f d" % [age, lifespan]
