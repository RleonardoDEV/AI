class_name WorldTools
extends RefCounted
## Every world-altering operation, in one module.
##
## Both the player's god tools and the random world events call these, so a
## meteor the player drops and a meteor the world throws behave identically —
## no duplicated logic, and events are always testable headlessly.

enum Tool { INSPECT, RAIN, FIRE, WATER, PLANT, ROCK, METEOR, VOLCANO, ICE, WIND, CREATURE }

const TOOL_NAMES: PackedStringArray = [
	"Inspect", "Rain", "Fire", "Water", "Plant", "Rock",
	"Meteor", "Volcano", "Ice", "Wind", "Creature",
]
## Captions that fit under a 30px icon without being truncated mid-word.
const TOOL_SHORT: PackedStringArray = [
	"LOOK", "RAIN", "FIRE", "WATER", "PLANT", "ROCK",
	"METEOR", "VOLC", "ICE", "WIND", "LIFE",
]

# --------------------------------------------------------------------------
# Painting tools
# --------------------------------------------------------------------------
static func rain(ctx: SimContext, center: Vector2, radius: float, strength: float = 0.5) -> void:
	var world := ctx.world
	_for_disc(world, center, radius, func(i: int, t: float) -> void:
		if Terrain.is_water(world.terrain[i]):
			return
		world.add_water(i, strength * t * 0.9)
		world.fire[i] = maxf(0.0, world.fire[i] - strength * t * 1.5)
		world.moisture[i] = minf(1.0, world.moisture[i] + strength * t * 0.05)
	)

static func ignite(ctx: SimContext, center: Vector2, radius: float, strength: float = 0.7) -> int:
	# Written as an explicit loop rather than via _for_disc: GDScript lambdas
	# capture by value, so a counter mutated inside one would be discarded.
	var world := ctx.world
	var lit := 0
	var r := int(ceil(radius))
	var cx := int(center.x)
	var cy := int(center.y)
	var r2 := radius * radius
	for dy in range(-r, r + 1):
		var y := cy + dy
		if y < 0 or y >= world.h:
			continue
		for dx in range(-r, r + 1):
			var x := cx + dx
			if x < 0 or x >= world.w:
				continue
			var d2 := float(dx * dx + dy * dy)
			if d2 > r2:
				continue
			var t: float = 1.0 - sqrt(d2) / maxf(0.001, radius)
			if t < 0.25:
				continue
			if world.ignite(y * world.w + x, strength * t):
				lit += 1
	if lit > 0:
		EventBus.fx_burst.emit(center, EventBus.FX_IGNITE, radius)
	return lit

static func flood(ctx: SimContext, center: Vector2, radius: float) -> void:
	var world := ctx.world
	_for_disc(world, center, radius, func(i: int, t: float) -> void:
		if t < 0.3:
			return
		# Sink the ground so the depth gradient reads correctly.
		world.elevation[i] = minf(world.elevation[i], GameConfig.SEA_LEVEL - 0.02 - t * 0.06)
		world.mark_modified(i)
		world.snow[i] = 0.0
		world.fire[i] = 0.0
		world.set_terrain(i, Terrain.T.SHALLOW if t < 0.65 else Terrain.T.WATER)
	)
	EventBus.fx_burst.emit(center, EventBus.FX_SPLASH, radius)

static func plant(ctx: SimContext, center: Vector2, radius: float, flora: FloraSystem) -> void:
	var world := ctx.world
	var rng := ctx.rng
	_for_disc(world, center, radius, func(i: int, t: float) -> void:
		var terr: int = world.terrain[i]
		if Terrain.is_water(terr) or terr == Terrain.T.LAVA:
			return
		if terr == Terrain.T.SAND or terr == Terrain.T.ASH or terr == Terrain.T.DIRT:
			world.set_terrain(i, Terrain.T.GRASS)
		var fert: float = Terrain.FERTILITY[world.terrain[i]]
		world.veg[i] = minf(fert, world.veg[i] + t * 0.9)
		world.moisture[i] = minf(1.0, world.moisture[i] + t * 0.1)
		world.mark_dirty(i)
	)
	if flora != null:
		var tries := int(radius * 0.8) + 1
		for k in tries:
			var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * radius
			if p.x < 1.0 or p.y < 1.0 or p.x >= float(world.w) - 1.0 or p.y >= float(world.h) - 1.0:
				continue
			var j := world.idx_at(p)
			if Terrain.FERTILITY[world.terrain[j]] < 0.3:
				continue
			var is_tree := rng.randf() < 0.55
			flora.add(p, rng.randi_range(0, PixelArt.TREE_VARIANTS - 1) if is_tree else rng.randi_range(0, 7),
					0, 0 if is_tree else 1, rng)
	EventBus.fx_burst.emit(center, EventBus.FX_BLOOM, radius)

static func raise_rock(ctx: SimContext, center: Vector2, radius: float) -> void:
	var world := ctx.world
	_for_disc(world, center, radius, func(i: int, t: float) -> void:
		world.elevation[i] = clampf(world.elevation[i] + t * 0.22, 0.0, 1.0)
		world.mark_modified(i)
		world.fire[i] = 0.0
		world.water[i] = 0.0
		if t > 0.35:
			world.set_terrain(i, Terrain.T.ROCK)
		world.shade[i] = clampi(int(float(world.shade[i]) + t * 70.0), 0, 255)
		world.mark_dirty(i)
	)
	EventBus.fx_burst.emit(center, EventBus.FX_DUST, radius)

static func freeze(ctx: SimContext, center: Vector2, radius: float) -> void:
	var world := ctx.world
	_for_disc(world, center, radius, func(i: int, t: float) -> void:
		world.fire[i] = 0.0
		world.temperature[i] -= t * 34.0
		if Terrain.is_water(world.terrain[i]):
			if t > 0.5:
				world.set_terrain(i, Terrain.T.ICE)
		else:
			world.snow[i] = minf(1.0, world.snow[i] + t * 1.1)
		world.mark_dirty(i)
	)
	EventBus.fx_burst.emit(center, EventBus.FX_FROST, radius)

static func gust(ctx: SimContext, center: Vector2, dir: Vector2, radius: float, strength: float) -> void:
	var mgr = ctx.entities
	var ids: PackedInt32Array = mgr.grid.query(center.x, center.y, radius)
	var d := dir.normalized()
	for k in ids.size():
		var c: Creature = mgr.creatures[ids[k]]
		if not c.alive:
			continue
		var t: float = clampf(1.0 - c.pos.distance_to(center) / radius, 0.0, 1.0)
		c.vel += d * strength * t * 8.0
		c.fear = minf(1.0, c.fear + t * 0.4)
	# Fan the flames.
	var world := ctx.world
	_for_disc(world, center, radius, func(i: int, t: float) -> void:
		if world.fire[i] > 0.02:
			world.fire[i] = minf(1.0, world.fire[i] + t * 0.15)
	)
	EventBus.fx_burst.emit(center, EventBus.FX_GUST, radius)

# --------------------------------------------------------------------------
# Cataclysms
# --------------------------------------------------------------------------
static func meteor(ctx: SimContext, center: Vector2, power: float = 1.0) -> void:
	var world := ctx.world
	var radius: float = 6.0 + power * 9.0
	# Crater: molten core, scorched floor, raised rim.
	_for_disc(world, center, radius * 1.35, func(i: int, t: float) -> void:
		var d := 1.0 - t
		world.mark_modified(i)
		if t > 0.78:
			world.elevation[i] = clampf(world.elevation[i] - 0.06 * power, 0.0, 1.0)
			world.set_terrain(i, Terrain.T.LAVA)
			world.temperature[i] += 160.0
		elif t > 0.52:
			world.set_terrain(i, Terrain.T.ASH)
			world.temperature[i] += 80.0 * t
			world.veg[i] = 0.0
		elif t > 0.34:
			world.elevation[i] = clampf(world.elevation[i] + 0.05 * power * (1.0 - d), 0.0, 1.0)
			if not Terrain.is_water(world.terrain[i]):
				world.set_terrain(i, Terrain.T.ROCK)
		else:
			world.veg[i] = maxf(0.0, world.veg[i] - t * 1.2)
			world.snow[i] = 0.0
			world.ignite(i, 0.5 + t * 0.4)
		world.mark_dirty(i)
	)
	# Kill anything at the epicentre outright.
	var mgr = ctx.entities
	var ids: PackedInt32Array = mgr.grid.query(center.x, center.y, radius)
	for k in ids.size():
		var c: Creature = mgr.creatures[ids[k]]
		if not c.alive:
			continue
		var dist := c.pos.distance_to(center)
		if dist < radius * 0.6:
			mgr.kill(ctx, c, Creature.Cause.FIRE)
		else:
			c.health -= 0.55 * power
			c.vel += (c.pos - center).normalized() * 14.0
			c.fear = 1.0
			c.mem_threat = center
			c.mem_threat_age = 0.0
	EventBus.fx_burst.emit(center, EventBus.FX_METEOR, radius)
	EventBus.screen_shake.emit(minf(26.0, 9.0 * power))
	EventBus.screen_flash.emit(Color(1.0, 0.85, 0.6), 0.75)

static func erupt(ctx: SimContext, center: Vector2, power: float = 1.0) -> void:
	var world := ctx.world
	var radius: float = 7.0 + power * 7.0
	_for_disc(world, center, radius, func(i: int, t: float) -> void:
		world.elevation[i] = clampf(world.elevation[i] + t * 0.3 * power, 0.0, 1.0)
		world.mark_modified(i)
		world.snow[i] = 0.0
		world.water[i] = 0.0
		world.temperature[i] += t * 120.0
		if t > 0.72:
			world.set_terrain(i, Terrain.T.LAVA)
		elif t > 0.4:
			world.set_terrain(i, Terrain.T.ASH)
			world.veg[i] = 0.0
		else:
			world.ignite(i, 0.4 + t * 0.5)
		world.mark_dirty(i)
	)
	EventBus.fx_burst.emit(center, EventBus.FX_ERUPT, radius)
	EventBus.screen_shake.emit(minf(20.0, 7.0 * power))

# --------------------------------------------------------------------------
# Life
# --------------------------------------------------------------------------
## Drops a creature: usually a descendant of a living species, occasionally a
## brand-new lineage seeded from a random archetype.
static func spawn_life(ctx: SimContext, center: Vector2, count: int = 1) -> int:
	var made := 0
	var living := ctx.registry.living()
	for k in count:
		var at := center + Vector2.from_angle(ctx.rng.randf() * TAU) * ctx.rng.randf() * 2.5
		at.x = clampf(at.x, 1.0, float(ctx.world.w) - 2.0)
		at.y = clampf(at.y, 1.0, float(ctx.world.h) - 2.0)
		var sp: Species = null
		var genome: PackedFloat32Array
		if living.is_empty() or ctx.rng.randf() < 0.22:
			var profiles := SpeciesRegistry.starting_profiles()
			var pick: Dictionary = profiles[ctx.rng.randi() % profiles.size()]
			genome = DNA.from_profile(pick["genes"], ctx.rng, 0.12)
			sp = ctx.registry.classify(-1, genome, ctx.tick, ctx.climate.year, 1, ctx.rng)
			sp.family = int(pick["name_family"])
		else:
			sp = living[ctx.rng.randi() % living.size()]
			genome = sp.centroid.duplicate()
			DNA.mutate(genome, ctx.rng, 0.3, 0.05)
		var c = ctx.entities.spawn(ctx, sp, genome, at, 1)
		if c != null:
			made += 1
	if made > 0:
		EventBus.fx_burst.emit(center, EventBus.FX_SPAWN, 4.0)
	return made

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
## Visits every cell in a disc, passing the cell index and a 0..1 falloff where
## 1 is the centre.
static func _for_disc(world: WorldData, center: Vector2, radius: float, fn: Callable) -> void:
	# Terrain edits inside a disc defer their shoreline recomputation to a
	# single regional pass (see WorldData.begin_bulk_edit).
	world.begin_bulk_edit()
	var r := int(ceil(radius))
	var cx := int(center.x)
	var cy := int(center.y)
	var r2 := radius * radius
	for dy in range(-r, r + 1):
		var y := cy + dy
		if y < 0 or y >= world.h:
			continue
		for dx in range(-r, r + 1):
			var x := cx + dx
			if x < 0 or x >= world.w:
				continue
			var d2 := float(dx * dx + dy * dy)
			if d2 > r2:
				continue
			var t: float = 1.0 - sqrt(d2) / maxf(0.001, radius)
			fn.call(y * world.w + x, t)
	world.end_bulk_edit()
