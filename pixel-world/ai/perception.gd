class_name Perception
extends RefCounted
## Sensing helpers. Results land in static fields instead of returned
## dictionaries so a scan allocates nothing.
##
## Searches are deliberately sparse: a creature fires 12 directional probes at
## two ranges instead of scanning its whole vision disc, and only when its
## search cooldown expires. That is both cheaper and more lifelike — animals
## remember where food was and head back there.

const PROBE_COUNT: int = 12
## Probes actually fired per search (a rotating subset of PROBE_COUNT).
const PROBE_USED: int = 6
## Relative radii probed when looking for fire (near rings first).
const FIRE_RINGS: PackedFloat32Array = [0.12, 0.3, 0.55, 1.0]
## Upper bound on neighbours examined per scan.
const MAX_CANDIDATES: int = 24
static var _dirs: PackedVector2Array = PackedVector2Array()

# Scan results
static var threat_id: int = -1
static var threat_pos: Vector2 = Vector2.ZERO
static var threat_dist: float = 0.0
static var prey_id: int = -1
static var prey_pos: Vector2 = Vector2.ZERO
static var prey_dist: float = 0.0
static var mate_id: int = -1
static var mate_pos: Vector2 = Vector2.ZERO
static var flock_center: Vector2 = Vector2.ZERO
static var flock_vel: Vector2 = Vector2.ZERO
static var flock_count: int = 0
static var separation: Vector2 = Vector2.ZERO
static var crowding: int = 0

static func _ensure_dirs() -> void:
	if _dirs.size() == PROBE_COUNT:
		return
	_dirs.resize(0)
	for i in PROBE_COUNT:
		_dirs.append(Vector2.from_angle(float(i) * TAU / float(PROBE_COUNT)))

## Best nearby edible cell for a plant eater, or (-1,-1).
static func find_forage(ctx: SimContext, c: Creature) -> Vector2:
	_ensure_dirs()
	var world := ctx.world
	var best := -1.0
	var best_pos := Vector2(-1, -1)
	var r := c.vision
	# Rotating probe subset keyed off the creature id: gives each animal a
	# different search pattern without a per-probe rotation (sin/cos here was
	# the single most expensive thing in the update loop).
	var base := c.id % PROBE_COUNT
	var w := world.w
	var maxx := float(w) - 1.0
	var maxy := float(world.h) - 1.0
	var wet_ok: bool = c.aquatic >= 0.6
	for k in PROBE_USED:
		var d: Vector2 = _dirs[(base + k * 3) % PROBE_COUNT]
		for step in 2:
			var dist := r * (0.45 + 0.55 * float(step))
			var p := c.pos + d * dist
			if p.x < 1.0 or p.y < 1.0 or p.x >= maxx or p.y >= maxy:
				continue
			# Index inlined: the bounds check above makes clamping redundant,
			# and this loop runs tens of times per search.
			var j: int = int(p.y) * w + int(p.x)
			var v: float = world.veg[j]
			if v < 0.08:
				continue
			if world.fire[j] > 0.02:
				continue
			if not wet_ok and world.terrain[j] <= Terrain.T.SHALLOW:
				continue
			# Prefer rich cells that are close.
			var score := v / (1.0 + dist * 0.09)
			if score > best:
				best = score
				best_pos = p
	# Fall back on memory if nothing is in range.
	if best_pos.x < 0.0 and c.mem_food.x >= 0.0:
		var j2 := world.idx_at(c.mem_food)
		if world.veg[j2] > 0.12:
			return c.mem_food
	return best_pos

## Nearest drinkable cell, or (-1,-1).
static func find_water(ctx: SimContext, c: Creature) -> Vector2:
	_ensure_dirs()
	var world := ctx.world
	var r: float = c.vision * 1.35
	var best := INF
	var best_pos := Vector2(-1, -1)
	var base := (c.id + 5) % PROBE_COUNT
	var w := world.w
	var maxx := float(w) - 1.0
	var maxy := float(world.h) - 1.0
	var can_swim: bool = c.aquatic >= 0.5
	for k in PROBE_USED:
		var d: Vector2 = _dirs[(base + k * 3) % PROBE_COUNT]
		for step in 3:
			var dist := r * (0.3 + 0.3 * float(step))
			var p := c.pos + d * dist
			if p.x < 1.0 or p.y < 1.0 or p.x >= maxx or p.y >= maxy:
				continue
			var j: int = int(p.y) * w + int(p.x)
			var t: int = world.terrain[j]
			# Drinkability test inlined (see WorldData.is_drinkable).
			if not (t <= Terrain.T.SHALLOW or world.shore[j] >= 95
					or world.water[j] > 0.08 or world.snow[j] > 0.2):
				continue
			# Skip open water it cannot enter — the bank beside it is drinkable.
			if t <= Terrain.T.WATER and not can_swim:
				continue
			if t == Terrain.T.LAVA:
				continue
			if dist < best:
				best = dist
				best_pos = p
	if best_pos.x < 0.0 and c.mem_water.x >= 0.0:
		return c.mem_water
	return best_pos

## Direction that most improves thermal comfort, or Vector2.ZERO.
static func find_comfort(ctx: SimContext, c: Creature) -> Vector2:
	_ensure_dirs()
	var world := ctx.world
	var w := world.w
	var here := world.temperature[int(c.pos.y) * w + int(c.pos.x)]
	var best_err := absf(here - c.temp_pref)
	var best_pos := Vector2(-1, -1)
	var maxx := float(w) - 1.0
	var maxy := float(world.h) - 1.0
	for i in PROBE_USED:
		var p := c.pos + _dirs[(i * 3) % PROBE_COUNT] * c.vision * 1.6
		if p.x < 1.0 or p.y < 1.0 or p.x >= maxx or p.y >= maxy:
			continue
		var j: int = int(p.y) * w + int(p.x)
		if world.terrain[j] <= Terrain.T.SHALLOW and c.aquatic < 0.6:
			continue
		var err := absf(world.temperature[j] - c.temp_pref)
		if err < best_err - 0.5:
			best_err = err
			best_pos = p
	return best_pos

## Nearest fire to the creature, or (-1,-1). Probed *locally* around the
## animal rather than by sampling the global burning list: in a firestorm the
## global list is thousands of cells long, and a strided sample of it routinely
## reported the fire as far away while the creature stood inside it.
static func find_fire(ctx: SimContext, c: Creature, radius: float) -> Vector2:
	var world := ctx.world
	if world.burning_cells.is_empty():
		return Vector2(-1, -1)
	_ensure_dirs()
	var w := world.w
	var h := world.h
	var cx := int(c.pos.x)
	var cy := int(c.pos.y)
	# Standing in it?
	if world.fire[cy * w + cx] > 0.03:
		return c.pos
	var base := c.id % PROBE_COUNT
	for ring in FIRE_RINGS:
		var rr: float = radius * ring
		for k in PROBE_COUNT:
			var d: Vector2 = _dirs[(base + k) % PROBE_COUNT]
			var x := cx + int(d.x * rr)
			var y := cy + int(d.y * rr)
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			if world.fire[y * w + x] > 0.03:
				return Vector2(float(x) + 0.5, float(y) + 0.5)
	return Vector2(-1, -1)

## Populates the static scan fields: threats, prey, mates and flock forces.
static func scan(ctx: SimContext, c: Creature) -> void:
	threat_id = -1
	prey_id = -1
	mate_id = -1
	flock_count = 0
	crowding = 0
	flock_center = Vector2.ZERO
	flock_vel = Vector2.ZERO
	separation = Vector2.ZERO
	threat_dist = INF
	prey_dist = INF
	var mate_best := INF

	var mgr = ctx.entities
	var radius: float = minf(c.vision, 11.0)
	var ids: PackedInt32Array = mgr.grid.query(c.pos.x, c.pos.y, radius, MAX_CANDIDATES, c.id)
	var r2 := radius * radius
	var want_mate: bool = c.repro_drive > 0.40 and c.is_adult() and c.breed_cooldown <= 0.0
	var carn := c.is_carnivore()
	# Herds cluster, so a bucket neighbourhood can hold hundreds of animals and
	# a naive pass over it is the O(n^2) trap that kills the frame rate. Sample
	# at most MAX_CANDIDATES of them, strided across the list: perception stays
	# statistically the same and the cost is bounded.
	var n := ids.size()
	var step: int = 1 if n <= MAX_CANDIDATES else int(ceil(float(n) / float(MAX_CANDIDATES)))
	var k := (c.id % step) if step > 1 else 0
	var creatures: Array[Creature] = mgr.creatures
	var my_pos := c.pos
	var my_sp := c.species_id
	var my_size := c.body_size
	var big_prey := my_size * 1.15
	var small_threat := my_size * 0.72
	while k < n:
		var oid: int = ids[k]
		k += step
		if oid == c.id:
			continue
		var o: Creature = creatures[oid]
		if not o.alive:
			continue
		var off := o.pos - my_pos
		var d2 := off.length_squared()
		if d2 > r2:
			continue
		var same: bool = o.species_id == my_sp
		# --- Threat: a bigger meat-eater of another species
		if not same and o.diet > 0.62 and o.body_size > small_threat:
			if d2 < threat_dist:
				threat_dist = d2
				threat_id = oid
				threat_pos = o.pos
		# --- Prey: smaller animal of another species
		elif carn and not same and o.body_size < big_prey:
			if d2 < prey_dist:
				prey_dist = d2
				prey_id = oid
				prey_pos = o.pos
		# --- Mate: same species, willing
		if want_mate and same and o.is_adult() and o.repro_drive > 0.28 and o.breed_cooldown <= 0.0:
			if d2 < mate_best:
				mate_best = d2
				mate_id = oid
				mate_pos = o.pos
		# --- Flock forces from same-species neighbours
		if same and d2 < 64.0:
			flock_count += 1
			flock_center += o.pos
			flock_vel += o.vel
			if d2 < 4.0 and d2 > 0.0001:
				separation -= off / maxf(0.35, d2)
				crowding += 1
	if flock_count > 0:
		flock_center /= float(flock_count)
		flock_vel /= float(flock_count)
	if threat_id >= 0:
		threat_dist = sqrt(threat_dist)
	if prey_id >= 0:
		prey_dist = sqrt(prey_dist)
