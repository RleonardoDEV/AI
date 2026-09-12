class_name SpeciesRegistry
extends RefCounted
## Owns the species list and decides when a lineage has become a new species.
##
## Speciation is emergent, not scripted: every newborn is compared against its
## parent species centroid, and once the weighted genetic distance passes a
## threshold the offspring founds a new species that records its ancestor. That
## parent/child chain is exactly what the evolutionary tree screen renders.

const SPECIATION_DIST: float = 0.155
## A species must reach this many members before it can spawn descendants,
## so a single freak mutant does not fragment the tree.
const MIN_PARENT_POP: int = 3

var species: Array[Species] = []
var by_id: Dictionary = {}
var next_id: int = 0
var world_seed: int = 0
var _slot_owner: PackedInt32Array = PackedInt32Array()

# Aggregate history
var total_species_created: int = 0
var total_extinctions: int = 0

func _init(seed_value: int = 0) -> void:
	world_seed = seed_value
	_slot_owner.resize(GameConfig.MAX_SPECIES_SLOTS)
	for i in _slot_owner.size():
		_slot_owner[i] = -1

# --------------------------------------------------------------------------
# Starting fauna
# --------------------------------------------------------------------------
## Trophic archetypes the world starts with. Values are 0..1 positions inside
## each gene's range; everything else drifts from here.
static func starting_profiles() -> Array[Dictionary]:
	var G := DNA.G
	return [
		{ # Grazer: social, placid, plentiful
			"name_family": PixelArt.Family.QUADRUPED,
			"genes": {G.SPEED: 0.34, G.SIZE: 0.46, G.VISION: 0.34, G.AGGRESSION: 0.07,
				G.METABOLISM: 0.40, G.FERTILITY: 0.74, G.LIFESPAN: 0.42, G.TEMP_PREF: 0.62,
				G.DIET: 0.04, G.HUE: 0.48, G.SAT: 0.52, G.VAL: 0.62, G.SOCIAL: 0.82,
				G.FEAR: 0.62, G.STAMINA: 0.45, G.AQUATIC: 0.12},
		},
		{ # Hopper: small, fast, skittish
			"name_family": PixelArt.Family.QUADRUPED,
			"genes": {G.SPEED: 0.72, G.SIZE: 0.20, G.VISION: 0.46, G.AGGRESSION: 0.05,
				G.METABOLISM: 0.62, G.FERTILITY: 0.88, G.LIFESPAN: 0.22, G.TEMP_PREF: 0.58,
				G.DIET: 0.03, G.HUE: 0.62, G.SAT: 0.60, G.VAL: 0.70, G.SOCIAL: 0.55,
				G.FEAR: 0.88, G.STAMINA: 0.68, G.AQUATIC: 0.08},
		},
		{ # Stalker: apex predator
			"name_family": PixelArt.Family.QUADRUPED,
			"genes": {G.SPEED: 0.62, G.SIZE: 0.66, G.VISION: 0.72, G.AGGRESSION: 0.86,
				G.METABOLISM: 0.46, G.FERTILITY: 0.34, G.LIFESPAN: 0.52, G.TEMP_PREF: 0.58,
				G.DIET: 0.96, G.HUE: 0.20, G.SAT: 0.70, G.VAL: 0.58, G.SOCIAL: 0.30,
				G.FEAR: 0.16, G.STAMINA: 0.58, G.AQUATIC: 0.16},
		},
		{ # Crawler: insect scavenger, breeds fast
			"name_family": PixelArt.Family.INSECT,
			"genes": {G.SPEED: 0.42, G.SIZE: 0.06, G.VISION: 0.20, G.AGGRESSION: 0.30,
				G.METABOLISM: 0.70, G.FERTILITY: 0.92, G.LIFESPAN: 0.10, G.TEMP_PREF: 0.68,
				G.DIET: 0.42, G.HUE: 0.30, G.SAT: 0.45, G.VAL: 0.40, G.SOCIAL: 0.68,
				G.FEAR: 0.50, G.STAMINA: 0.40, G.AQUATIC: 0.20},
		},
		{ # Skimmer: fast flyer, hunts insects
			"name_family": PixelArt.Family.AVIAN,
			"genes": {G.SPEED: 0.88, G.SIZE: 0.22, G.VISION: 0.84, G.AGGRESSION: 0.52,
				G.METABOLISM: 0.66, G.FERTILITY: 0.54, G.LIFESPAN: 0.30, G.TEMP_PREF: 0.60,
				G.DIET: 0.74, G.HUE: 0.72, G.SAT: 0.62, G.VAL: 0.78, G.SOCIAL: 0.62,
				G.FEAR: 0.58, G.STAMINA: 0.82, G.AQUATIC: 0.30},
		},
		{ # Lurker: ambush serpent
			"name_family": PixelArt.Family.SERPENT,
			"genes": {G.SPEED: 0.30, G.SIZE: 0.42, G.VISION: 0.52, G.AGGRESSION: 0.78,
				G.METABOLISM: 0.26, G.FERTILITY: 0.36, G.LIFESPAN: 0.62, G.TEMP_PREF: 0.74,
				G.DIET: 0.92, G.HUE: 0.12, G.SAT: 0.55, G.VAL: 0.45, G.SOCIAL: 0.10,
				G.FEAR: 0.22, G.STAMINA: 0.30, G.AQUATIC: 0.40},
		},
		{ # Wader: amphibious grazer
			"name_family": PixelArt.Family.AQUATIC,
			"genes": {G.SPEED: 0.48, G.SIZE: 0.38, G.VISION: 0.38, G.AGGRESSION: 0.18,
				G.METABOLISM: 0.45, G.FERTILITY: 0.72, G.LIFESPAN: 0.40, G.TEMP_PREF: 0.55,
				G.DIET: 0.16, G.HUE: 0.55, G.SAT: 0.58, G.VAL: 0.60, G.SOCIAL: 0.50,
				G.FEAR: 0.55, G.STAMINA: 0.50, G.AQUATIC: 0.95},
		},
		{ # Bulwark: slow, tough, thorny
			"name_family": PixelArt.Family.BLOB,
			"genes": {G.SPEED: 0.10, G.SIZE: 0.82, G.VISION: 0.22, G.AGGRESSION: 0.45,
				G.METABOLISM: 0.18, G.FERTILITY: 0.20, G.LIFESPAN: 0.86, G.TEMP_PREF: 0.50,
				G.DIET: 0.30, G.HUE: 0.82, G.SAT: 0.42, G.VAL: 0.52, G.SOCIAL: 0.25,
				G.FEAR: 0.12, G.STAMINA: 0.22, G.AQUATIC: 0.25},
		},
	]

func seed_initial(rng: RandomNumberGenerator) -> Array[Species]:
	var out: Array[Species] = []
	for p in starting_profiles():
		var genome := DNA.from_profile(p["genes"], rng, 0.05)
		var sp := _create(genome, int(p["name_family"]), -1, 0, 0, 1)
		out.append(sp)
	return out

# --------------------------------------------------------------------------
# Speciation
# --------------------------------------------------------------------------
## Returns the species a newborn belongs to, founding a new one if it has
## drifted far enough from its parent lineage.
func classify(parent_species_id: int, genome: PackedFloat32Array, tick: int,
		year: int, generation: int, rng: RandomNumberGenerator) -> Species:
	var parent: Species = by_id.get(parent_species_id, null)
	if parent == null:
		return _create(genome, PixelArt.Family.QUADRUPED, -1, tick, year, generation)
	var d := DNA.distance(genome, parent.centroid)
	if d > SPECIATION_DIST and parent.population >= MIN_PARENT_POP:
		var family := parent.family
		# A large jump occasionally reshapes the body plan itself.
		if rng.randf() < 0.18:
			family = rng.randi() % 6
		var sp := _create(genome, family, parent.id, tick, year, generation)
		parent.children.append(sp.id)
		return sp
	# Same species: nudge the centroid toward the newcomer.
	DNA.blend_into(parent.centroid, genome, 0.035)
	parent.color = DNA.color_of(parent.centroid)
	return parent

func _create(genome: PackedFloat32Array, family: int, parent_id: int,
		tick: int, year: int, generation: int) -> Species:
	var sp := Species.new()
	sp.id = next_id
	next_id += 1
	sp.name = NameGen.species_name(sp.id, world_seed)
	sp.epithet = NameGen.epithet(sp.id, world_seed)
	sp.family = family
	sp.centroid = genome.duplicate()
	sp.founder_genome = genome.duplicate()
	sp.parent_id = parent_id
	sp.founded_tick = tick
	sp.founded_year = year
	sp.founder_generation = generation
	sp.color = DNA.color_of(genome)
	sp.sprite_slot = _alloc_slot(sp.id)
	species.append(sp)
	by_id[sp.id] = sp
	total_species_created += 1
	EventBus.species_created.emit(sp)
	return sp

## Sprite slots are a fixed pool: prefer a free slot, then recycle the slot of
## an extinct species, then the least populous living one.
func _alloc_slot(owner_id: int) -> int:
	for i in _slot_owner.size():
		if _slot_owner[i] < 0:
			_slot_owner[i] = owner_id
			return i
	var worst := -1
	var worst_pop := 1 << 30
	for i in _slot_owner.size():
		var holder: Species = by_id.get(_slot_owner[i], null)
		if holder == null:
			_slot_owner[i] = owner_id
			return i
		var score: int = holder.population if not holder.extinct else -1
		if score < worst_pop:
			worst_pop = score
			worst = i
	if worst >= 0:
		_slot_owner[worst] = owner_id
		return worst
	return 0

# --------------------------------------------------------------------------
# Bookkeeping
# --------------------------------------------------------------------------
func on_birth(sp: Species) -> void:
	sp.population += 1
	sp.total_born += 1
	sp.peak_population = maxi(sp.peak_population, sp.population)
	if sp.extinct:
		sp.extinct = false
		sp.extinct_year = -1

func on_death(sp: Species, year: int) -> void:
	sp.population = maxi(0, sp.population - 1)
	sp.total_died += 1
	if sp.population == 0 and not sp.extinct:
		sp.extinct = true
		sp.extinct_year = year
		total_extinctions += 1

func living() -> Array[Species]:
	var out: Array[Species] = []
	for s in species:
		if s.population > 0:
			out.append(s)
	return out

func living_count() -> int:
	var n := 0
	for s in species:
		if s.population > 0:
			n += 1
	return n

func dominant() -> Species:
	var best: Species = null
	for s in species:
		if best == null or s.population > best.population:
			best = s
	return best

func get_species(id: int) -> Species:
	return by_id.get(id, null)

## Depth of a species in the phylogeny (0 = founding stock).
func depth_of(sp: Species) -> int:
	var d := 0
	var cur := sp
	while cur != null and cur.parent_id >= 0 and d < 64:
		cur = by_id.get(cur.parent_id, null)
		d += 1
	return d

func serialize() -> Dictionary:
	var arr: Array = []
	for s in species:
		arr.append(s.serialize())
	return {"next_id": next_id, "species": arr, "slots": _slot_owner,
			"created": total_species_created, "extinctions": total_extinctions}

func deserialize(d: Dictionary) -> void:
	species.clear()
	by_id.clear()
	next_id = int(d.get("next_id", 0))
	total_species_created = int(d.get("created", 0))
	total_extinctions = int(d.get("extinctions", 0))
	_slot_owner = PackedInt32Array(d.get("slots", _slot_owner))
	for raw in d.get("species", []):
		var s := Species.deserialize(raw)
		s.population = 0
		species.append(s)
		by_id[s.id] = s
