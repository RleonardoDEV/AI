class_name EntityManager
extends RefCounted
## Pooled creature and corpse storage, plus the per-tick update schedule.
##
## Creatures are allocated once and recycled: no allocation happens during
## play, which keeps frame times flat. They are updated on a *stride* — only
## 1/stride of the population each tick, with a proportionally larger dt — so
## raising the simulation speed to 100x costs no more CPU than 1x. Off-screen
## creatures take an extra stride multiplier on top (they effectively doze).

const CORPSE_POOL: int = 320
const DAY_SECONDS: float = float(GameConfig.TICKS_PER_DAY) * GameConfig.TICK_DT
## Population share above which a species starts suppressing its own breeding.
const DOMINANCE_SHARE: float = 0.42

var creatures: Array[Creature] = []
var alive_ids: PackedInt32Array = PackedInt32Array()
var free_ids: PackedInt32Array = PackedInt32Array()
var grid: SpatialGrid
var population: int = 0

# --- Corpse pool (structure of arrays) -----------------------------------
var corpse_pos: PackedVector2Array = PackedVector2Array()
var corpse_meat: PackedFloat32Array = PackedFloat32Array()
var corpse_life: PackedFloat32Array = PackedFloat32Array()
var corpse_color: PackedColorArray = PackedColorArray()
var corpse_active: PackedByteArray = PackedByteArray()
var corpse_count: int = 0
var _corpse_cursor: int = 0
## Compact list of occupied slots, rebuilt once per frame.
var _corpse_live: PackedInt32Array = PackedInt32Array()

func _init(world_w: int, world_h: int) -> void:
	grid = SpatialGrid.new(world_w, world_h, GameConfig.GRID_CELL)
	creatures.resize(GameConfig.MAX_CREATURES)
	free_ids.resize(GameConfig.MAX_CREATURES)
	for i in GameConfig.MAX_CREATURES:
		var c := Creature.new()
		c.id = i
		creatures[i] = c
		# Reverse order so ids are handed out ascending.
		free_ids[GameConfig.MAX_CREATURES - 1 - i] = i
	corpse_pos.resize(CORPSE_POOL)
	corpse_meat.resize(CORPSE_POOL)
	corpse_life.resize(CORPSE_POOL)
	corpse_color.resize(CORPSE_POOL)
	corpse_active.resize(CORPSE_POOL)

# --------------------------------------------------------------------------
# Spawning / killing
# --------------------------------------------------------------------------
func spawn(ctx: SimContext, sp: Species, genome: PackedFloat32Array, at: Vector2,
		generation: int) -> Creature:
	if free_ids.is_empty():
		return null
	var id: int = free_ids[free_ids.size() - 1]
	free_ids.remove_at(free_ids.size() - 1)
	var c: Creature = creatures[id]
	c.configure(sp, genome, at, generation, ctx.tick, ctx.rng)
	alive_ids.append(id)
	population += 1
	ctx.registry.on_birth(sp)
	ctx.stats.peak_population = maxi(ctx.stats.peak_population, population)
	EventBus.creature_born.emit(c)
	return c

func kill(ctx: SimContext, c: Creature, cause: int) -> void:
	if not c.alive:
		return
	c.alive = false
	population -= 1
	ctx.registry.on_death(c.species, ctx.climate.year)
	ctx.stats.note_death(cause)
	# Predation already transferred the energy; anything else leaves carrion.
	if cause != Creature.Cause.FIRE:
		_add_corpse(c)
	EventBus.fx_burst.emit(c.pos, EventBus.FX_DEATH, 1.0)
	EventBus.creature_died.emit(c, cause)

## Compacts the alive list; called once per tick batch.
func reap() -> void:
	var n := alive_ids.size()
	var write := 0
	for k in n:
		var id: int = alive_ids[k]
		if creatures[id].alive:
			alive_ids[write] = id
			write += 1
		else:
			free_ids.append(id)
	if write < n:
		alive_ids.resize(write)

func _add_corpse(c: Creature) -> void:
	var slot := -1
	for k in CORPSE_POOL:
		var i := (_corpse_cursor + k) % CORPSE_POOL
		if corpse_active[i] == 0:
			slot = i
			break
	if slot < 0:
		# Pool exhausted: overwrite the oldest.
		slot = _corpse_cursor
	else:
		corpse_count += 1
	_corpse_cursor = (slot + 1) % CORPSE_POOL
	corpse_pos[slot] = c.pos
	corpse_meat[slot] = c.meat_value()
	corpse_life[slot] = 22.0 + c.body_size * 14.0
	corpse_color[slot] = c.color.darkened(0.45)
	corpse_active[slot] = 1

## Decays carrion; rotted remains fertilise the soil. Also refreshes the
## compact live list used by scavenging lookups.
func update_corpses(ctx: SimContext, dt: float) -> void:
	_corpse_live.resize(0)
	if corpse_count <= 0:
		return
	var world := ctx.world
	for i in CORPSE_POOL:
		if corpse_active[i] == 0:
			continue
		corpse_life[i] -= dt
		if corpse_life[i] <= 0.0:
			corpse_active[i] = 0
			corpse_count -= 1
			var j := world.idx_at(corpse_pos[i])
			var fert: float = Terrain.FERTILITY[world.terrain[j]]
			if fert > 0.1:
				world.veg[j] = minf(fert, world.veg[j] + corpse_meat[i] * 0.5)
				world.mark_dirty(j)
			continue
		_corpse_live.append(i)

## Occupied corpse slots (compact, refreshed once per frame).
func live_corpses() -> PackedInt32Array:
	return _corpse_live

## 0..1 remaining freshness of a corpse, used to fade it out.
func corpse_fade(i: int) -> float:
	return clampf(corpse_life[i] / 20.0, 0.0, 1.0)

## Nearest carrion within radius, or -1.
func find_corpse(at: Vector2, radius: float) -> int:
	if corpse_count <= 0:
		return -1
	var best := radius * radius
	var found := -1
	for k in _corpse_live.size():
		var i: int = _corpse_live[k]
		if corpse_active[i] == 0:
			continue
		var d2 := corpse_pos[i].distance_squared_to(at)
		if d2 < best:
			best = d2
			found = i
	return found

func consume_corpse(i: int, amount: float) -> float:
	if corpse_active[i] == 0:
		return 0.0
	var take: float = minf(corpse_meat[i], amount)
	corpse_meat[i] -= take
	if corpse_meat[i] <= 0.02:
		corpse_active[i] = 0
		corpse_count -= 1
	return take

# --------------------------------------------------------------------------
# Reproduction
# --------------------------------------------------------------------------
## Sexual reproduction between two willing adults of the same species.
## Offspring inherit a crossover of both genomes plus mutation, and the
## registry decides whether the result is still the same species.
func try_reproduce(ctx: SimContext, a: Creature, b: Creature) -> Creature:
	if population >= GameConfig.MAX_CREATURES:
		return null
	if a.breed_cooldown > 0.0 or b.breed_cooldown > 0.0:
		return null
	if a.energy < 0.34 or b.energy < 0.34:
		return null
	if not a.is_adult() or not b.is_adult():
		return null
	# Density stress, measured among *conspecifics* only. Counting every nearby
	# animal meant predators — which by definition live inside prey herds —
	# were permanently blocked from breeding and went extinct in every run.
	var crowd_pressure: float = clampf(float(_same_species_near(a, 6.0)) / 9.0, 0.0, 1.0)
	if population > GameConfig.SOFT_POP_CAP:
		crowd_pressure = maxf(crowd_pressure,
			float(population - GameConfig.SOFT_POP_CAP) / float(GameConfig.MAX_CREATURES - GameConfig.SOFT_POP_CAP))
	# Interspecific competition: a species that already owns most of the
	# biosphere breeds against rising resistance. Without it, whichever
	# r-strategist wins first crowds every other lineage off the map and the
	# world becomes one colour.
	if population > 40:
		var share := float(a.species.population) / float(population)
		if share > DOMINANCE_SHARE:
			crowd_pressure = maxf(crowd_pressure,
					clampf((share - DOMINANCE_SHARE) / (1.0 - DOMINANCE_SHARE), 0.0, 0.85))
	if ctx.rng.randf() < crowd_pressure * 0.9:
		a.breed_cooldown = 3.0
		return null

	var genome := DNA.crossover(a.dna, b.dna, ctx.rng)
	var muts := DNA.mutate(genome, ctx.rng, 0.24, 0.025)
	ctx.stats.note_mutations(muts)
	var gen: int = maxi(a.generation, b.generation) + 1
	var sp := ctx.registry.classify(a.species_id, genome, ctx.tick, ctx.climate.year, gen, ctx.rng)
	var offset := Vector2.from_angle(ctx.rng.randf() * TAU) * ctx.rng.randf_range(0.6, 1.8)
	var child := spawn(ctx, sp, genome, a.pos + offset, gen)
	if child == null:
		return null
	# Newborns inherit what their parents knew: where the water and the good
	# grazing were. Without this, every generation has to rediscover the map
	# and populations collapse around unlucky births.
	child.mem_water = a.mem_water if a.mem_water.x >= 0.0 else b.mem_water
	child.mem_food = a.mem_food if a.mem_food.x >= 0.0 else b.mem_food
	child.mem_home = a.pos
	var cost := 0.30 + a.body_size * 0.08
	a.energy = maxf(0.05, a.energy - cost)
	b.energy = maxf(0.05, b.energy - cost * 0.7)
	a.repro_drive = 0.0
	b.repro_drive = 0.0
	var cd := 4.0 + (1.0 - a.fertility) * 13.0
	a.breed_cooldown = cd
	b.breed_cooldown = cd * 0.8
	ctx.stats.note_birth()
	EventBus.fx_burst.emit(child.pos, EventBus.FX_BIRTH, 1.0)
	return child

## Counts nearby animals of the same species (bounded grid query).
func _same_species_near(c: Creature, radius: float) -> int:
	var ids: PackedInt32Array = grid.query(c.pos.x, c.pos.y, radius, 28, c.id)
	var n := 0
	var r2 := radius * radius
	for k in ids.size():
		var o: Creature = creatures[ids[k]]
		if o.alive and o.species_id == c.species_id and o.pos.distance_squared_to(c.pos) < r2:
			n += 1
	return n

## Fallback for highly fertile r-strategists: lets a lone survivor rebuild a
## population instead of the world going sterile after a catastrophe.
func try_bud(ctx: SimContext, c: Creature) -> Creature:
	if population >= GameConfig.SOFT_POP_CAP:
		return null
	if c.fertility < 0.72 or c.energy < 0.72 or c.breed_cooldown > 0.0:
		return null
	var genome := c.dna.duplicate()
	var muts := DNA.mutate(genome, ctx.rng, 0.30, 0.04)
	ctx.stats.note_mutations(muts)
	var gen := c.generation + 1
	var sp := ctx.registry.classify(c.species_id, genome, ctx.tick, ctx.climate.year, gen, ctx.rng)
	var child := spawn(ctx, sp, genome, c.pos + Vector2.from_angle(ctx.rng.randf() * TAU), gen)
	if child == null:
		return null
	child.mem_water = c.mem_water
	child.mem_food = c.mem_food
	c.energy -= 0.42
	c.breed_cooldown = 14.0
	c.repro_drive = 0.0
	ctx.stats.note_birth()
	EventBus.fx_burst.emit(child.pos, EventBus.FX_BIRTH, 1.0)
	return child

# --------------------------------------------------------------------------
# Update schedule
# --------------------------------------------------------------------------
func rebuild_grid() -> void:
	grid.clear()
	for k in alive_ids.size():
		var id: int = alive_ids[k]
		var c: Creature = creatures[id]
		if c.alive:
			grid.insert(id, c.pos.x, c.pos.y)

func update(ctx: SimContext) -> void:
	var stride: int = maxi(1, ctx.stride)
	var tick := ctx.tick
	var base_dt := ctx.dt
	for k in alive_ids.size():
		var id: int = alive_ids[k]
		var c: Creature = creatures[id]
		if not c.alive:
			continue
		var step: int = stride * c.lod
		if step > 1 and ((tick + id) % step) != 0:
			continue
		_update_one(ctx, c, base_dt * float(step))

func _update_one(ctx: SimContext, c: Creature, dt: float) -> void:
	var world := ctx.world
	var cell := world.idx_at(c.pos)

	# --- Needs ------------------------------------------------------------
	c.age += dt / DAY_SECONDS
	var local_temp: float = world.temperature[cell]
	var heat_stress: float = clampf((local_temp - 24.0) / 22.0, 0.0, 1.4)
	c.hunger = minf(1.0, c.hunger + dt * 0.0155 * c.metabolism * (1.0 - 0.40 * c.diet))
	c.thirst = minf(1.0, c.thirst + dt * 0.0130 * (1.0 + heat_stress * 0.8))
	c.energy = maxf(0.0, c.energy - dt * 0.0042 * c.metabolism)
	c.breed_cooldown = maxf(0.0, c.breed_cooldown - dt)
	c.fear = maxf(0.0, c.fear - dt * 0.35)

	# --- Damage sources ---------------------------------------------------
	var dmg := 0.0
	if c.hunger >= 0.995:
		dmg += dt * 0.055
	if c.thirst >= 0.995:
		dmg += dt * 0.070
	if c.energy <= 0.001:
		dmg += dt * 0.03
	var terr: int = world.terrain[cell]
	if world.fire[cell] > 0.08:
		dmg += dt * 0.62
	if terr == Terrain.T.LAVA:
		dmg += dt * 3.0
	if Terrain.is_deep_water(terr) and c.aquatic < 0.42:
		dmg += dt * 0.24 * (1.0 - c.aquatic * 2.0)
	elif not Terrain.is_water(terr) and c.aquatic > 0.9:
		dmg += dt * 0.10
	var comfort_err := absf(local_temp - c.temp_pref)
	var tolerance := 16.0 + c.stamina * 5.0
	if comfort_err > tolerance:
		dmg += (comfort_err - tolerance) * 0.0022 * dt
	if c.age > c.lifespan:
		dmg += dt * 0.22
	elif c.age > c.lifespan * 0.82:
		dmg += dt * 0.006

	if dmg > 0.0:
		c.health -= dmg
	elif c.hunger < 0.6 and c.thirst < 0.6 and c.energy > 0.45:
		c.health = minf(1.0, c.health + dt * 0.022)

	if c.health <= 0.0:
		kill(ctx, c, _cause_of_death(ctx, c, cell))
		return

	# --- Reproductive drive ----------------------------------------------
	if c.is_adult() and c.energy > 0.5 and c.health > 0.62 and c.hunger < 0.7:
		c.repro_drive = minf(1.0, c.repro_drive + dt * 0.090 * (0.35 + c.fertility))
		if c.repro_drive > 0.97:
			try_bud(ctx, c)
	else:
		c.repro_drive = maxf(0.0, c.repro_drive - dt * 0.02)

	# --- Scavenging -------------------------------------------------------
	if c.diet > 0.38 and c.hunger > 0.45 and c.state != Creature.State.FLEE:
		var ci := find_corpse(c.pos, 2.2)
		if ci >= 0:
			var got := consume_corpse(ci, dt * 0.6)
			if got > 0.0:
				c.hunger = maxf(0.0, c.hunger - got * 1.6)
				c.energy = minf(1.0, c.energy + got * 1.0)

	Brain.think_and_act(ctx, c, dt)

func _cause_of_death(ctx: SimContext, c: Creature, cell: int) -> int:
	var world := ctx.world
	if world.fire[cell] > 0.08:
		return Creature.Cause.FIRE
	if world.terrain[cell] == Terrain.T.LAVA:
		return Creature.Cause.FIRE
	if Terrain.is_deep_water(world.terrain[cell]) and c.aquatic < 0.42:
		return Creature.Cause.DROWNING
	if c.age > c.lifespan:
		return Creature.Cause.OLD_AGE
	if c.thirst >= 0.99:
		return Creature.Cause.DEHYDRATION
	if c.hunger >= 0.99:
		return Creature.Cause.STARVATION
	var t: float = world.temperature[cell]
	if t < c.temp_pref - 11.0:
		return Creature.Cause.COLD
	if t > c.temp_pref + 11.0:
		return Creature.Cause.HEAT
	return Creature.Cause.STARVATION

## Assigns level-of-detail strides from the visible rectangle.
func refresh_lod(view: Rect2) -> void:
	var grown := view.grow(24.0)
	for k in alive_ids.size():
		var id: int = alive_ids[k]
		var c: Creature = creatures[id]
		if not c.alive:
			continue
		if view.has_point(c.pos):
			c.lod = 1
		elif grown.has_point(c.pos):
			c.lod = 2
		else:
			c.lod = 3
