class_name Simulation
extends RefCounted
## The orchestrator: owns every system and advances them under a fixed-timestep
## clock with a hard per-frame budget.
##
## Two ideas keep this running at 60 FPS from 1x all the way to 100x:
##
## 1. Time compression. Simulated time accumulates, and if a frame would need
##    more ticks than MAX_TICKS_PER_FRAME, the remaining time is folded into a
##    larger dt per tick instead of executing more ticks.
## 2. Adaptive striding. Creatures are updated in 1/stride slices per tick with
##    a proportionally larger dt, and the stride is chosen each frame to hit a
##    fixed budget of creature updates. Whole-grid systems (growth, thermal,
##    flora) run one chunk per frame for the same reason.
##
## The result: per-frame CPU cost is roughly flat with respect to both speed
## and population, and the simulation stays deterministic for a given seed and
## frame sequence.

## Creature updates allowed per frame. Movement stays smooth well below 60 Hz
## per creature, so this is the main lever on CPU cost. The budget is adaptive
## (see _tune_budget): the simulation trades update resolution for frame rate
## automatically, which is what lets the same build hold 60 FPS on a phone and
## still run rich on a desktop.
const CREATURE_UPDATES_MIN: int = 80
const CREATURE_UPDATES_MAX: int = 900
const FRAME_BUDGET_HIGH: float = 1.0 / 52.0
const FRAME_BUDGET_LOW: float = 1.0 / 75.0
const FIRE_SUBSTEPS_MAX: int = 4
const WATER_SUBSTEPS_MAX: int = 2
const LOD_REFRESH_FRAMES: int = 12

var world: WorldData
var entities: EntityManager
var registry: SpeciesRegistry
var climate: Climate
var weather: WeatherSystem
var stats: SimStats
var flora: FloraSystem
var fire: FireSystem
var water: WaterSystem
var growth: GrowthSystem
var ctx: SimContext
var rng: RandomNumberGenerator
var profiler: Profiler

var world_seed: int = 0
var tick: int = 0
var speed_index: int = 2
var stride: int = 2
var paused: bool = false
var elapsed_sim_time: float = 0.0

var _accum: float = 0.0
var _frame_counter: int = 0
var _last_ticks: int = 0
var _last_updates: int = 0
var _budget: float = 300.0
var _rollup_timer: float = 0.0

func speed() -> float:
	return GameConfig.SPEEDS[speed_index]

func speed_label() -> String:
	return GameConfig.SPEED_LABELS[speed_index]

func set_speed_index(i: int) -> void:
	speed_index = clampi(i, 0, GameConfig.SPEEDS.size() - 1)
	paused = speed_index == 0
	EventBus.speed_changed.emit(speed())

# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------
func build(seed_value: int) -> void:
	world_seed = seed_value
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	world = WorldData.new()
	WorldGen.generate(world, seed_value)

	registry = SpeciesRegistry.new(seed_value)
	climate = Climate.new()
	climate.advance(0.0)
	weather = WeatherSystem.new()
	stats = SimStats.new()
	entities = EntityManager.new(world.w, world.h)
	flora = FloraSystem.new()
	flora.populate_from_gen(rng)
	fire = FireSystem.new()
	water = WaterSystem.new()
	growth = GrowthSystem.new()

	profiler = Profiler.new()
	ctx = SimContext.new()
	ctx.world = world
	ctx.entities = entities
	ctx.registry = registry
	ctx.climate = climate
	ctx.weather = weather
	ctx.stats = stats
	ctx.rng = rng
	ctx.tick = 0
	ctx.view_rect = Rect2(0, 0, world.w, world.h)

	_seed_life()
	rollup()

## Places the founding populations where each archetype can actually survive.
func _seed_life() -> void:
	var founders := registry.seed_initial(rng)
	var per := int(GameConfig.START_CREATURES / maxi(1, founders.size()))
	# Remember where the plant eaters settled: dropping predators into empty
	# wilderness just starves them before they ever find prey.
	var prey_anchors: Array[Vector2] = []
	for sp in founders:
		var want := per
		# Predators start rarer than their prey.
		if sp.centroid[DNA.G.DIET] > 0.7:
			want = maxi(6, int(float(per) * 0.6))
		var placed := 0
		var attempts := 0
		var anchor := _find_habitat(sp)
		if sp.centroid[DNA.G.DIET] > 0.62 and not prey_anchors.is_empty():
			anchor = prey_anchors[rng.randi() % prey_anchors.size()] \
					+ Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 16.0)
			anchor.x = clampf(anchor.x, 3.0, float(world.w) - 4.0)
			anchor.y = clampf(anchor.y, 3.0, float(world.h) - 4.0)
		elif sp.centroid[DNA.G.DIET] < 0.5:
			prey_anchors.append(anchor)
		while placed < want and attempts < want * 90:
			attempts += 1
			# Founding clusters stay tight: a species scattered across the map
			# never meets a mate and dies out before it can breed.
			var spread: float = minf(8.0 + float(attempts) * 0.2, 26.0)
			var p := anchor + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * spread
			p.x = clampf(p.x, 2.0, float(world.w) - 3.0)
			p.y = clampf(p.y, 2.0, float(world.h) - 3.0)
			if not _habitable(sp, world.idx_at(p)):
				continue
			var genome := sp.centroid.duplicate()
			DNA.mutate(genome, rng, 0.3, 0.01)
			var c := entities.spawn(ctx, sp, genome, p, 1)
			if c != null:
				c.age = rng.randf_range(0.0, c.lifespan * 0.4)
				placed += 1
	entities.rebuild_grid()

func _find_habitat(sp: Species) -> Vector2:
	var best := Vector2(float(world.w) * 0.5, float(world.h) * 0.5)
	var best_score := -INF
	for attempt in 900:
		var x := rng.randi_range(3, world.w - 4)
		var y := rng.randi_range(3, world.h - 4)
		var i := y * world.w + x
		if not _habitable(sp, i):
			continue
		var score: float = world.veg[i] * 2.0
		score -= absf(world.temperature[i] - sp.centroid[DNA.G.TEMP_PREF]) * 0.14
		score += rng.randf() * 0.4
		if score > best_score:
			best_score = score
			best = Vector2(float(x) + 0.5, float(y) + 0.5)
	return best

func _habitable(sp: Species, i: int) -> bool:
	var t: int = world.terrain[i]
	var aq: float = sp.centroid[DNA.G.AQUATIC]
	if t == Terrain.T.LAVA:
		return false
	if Terrain.is_water(t):
		return aq > 0.55
	if aq > 0.9:
		return false
	if absf(world.temperature[i] - sp.centroid[DNA.G.TEMP_PREF]) > 22.0:
		return false
	return true

# --------------------------------------------------------------------------
# Main advance
# --------------------------------------------------------------------------
## Advances the world by one rendered frame. Returns the number of ticks run.
func advance(real_delta: float, view_rect: Rect2) -> int:
	_last_ticks = 0
	if paused:
		return 0
	_frame_counter += 1
	ctx.view_rect = view_rect

	_accum += speed() * real_delta
	var dt_per_tick := GameConfig.TICK_DT
	var ticks := int(_accum / dt_per_tick)
	if ticks <= 0:
		return 0
	if ticks > GameConfig.MAX_TICKS_PER_FRAME:
		# Fold the excess into a bigger dt rather than running more ticks.
		ticks = GameConfig.MAX_TICKS_PER_FRAME
		dt_per_tick = _accum / float(ticks)
	_accum -= float(ticks) * dt_per_tick
	var frame_dt := float(ticks) * dt_per_tick
	elapsed_sim_time += frame_dt

	# --- Creature scheduling ---------------------------------------------
	profiler.begin("grid")
	if _frame_counter % LOD_REFRESH_FRAMES == 0:
		entities.refresh_lod(view_rect)
	entities.rebuild_grid()
	profiler.end("grid")
	_tune_budget(real_delta)
	var pop: int = maxi(1, entities.population)
	stride = clampi(int(ceil(float(pop * ticks) / maxf(1.0, _budget))), 1, 16)
	ctx.stride = stride
	ctx.dt = dt_per_tick
	profiler.begin("creatures")
	for t in ticks:
		tick += 1
		ctx.tick = tick
		entities.update(ctx)
	entities.reap()
	profiler.end("creatures")
	_last_ticks = ticks
	_last_updates = int(float(pop * ticks) / float(stride))

	# --- World systems (per frame, with budgets) -------------------------
	profiler.begin("world")
	var fire_steps: int = clampi(ticks, 1, FIRE_SUBSTEPS_MAX)
	if not world.burning_cells.is_empty():
		for s in fire_steps:
			fire.update(ctx, frame_dt / float(fire_steps), weather.wind)
	var water_steps: int = clampi(ticks, 1, WATER_SUBSTEPS_MAX)
	if not world.wet_cells.is_empty():
		for s in water_steps:
			water.update(ctx, frame_dt / float(water_steps))
	profiler.end("world")
	profiler.begin("growth")
	growth.update(ctx, frame_dt)
	profiler.end("growth")
	profiler.begin("flora")
	flora.update(ctx, frame_dt)
	profiler.end("flora")
	profiler.begin("weather")
	weather.update(ctx, frame_dt, water, growth)
	entities.update_corpses(ctx, frame_dt)
	profiler.end("weather")

	# --- Calendar ---------------------------------------------------------
	var rolled := climate.advance(frame_dt)
	if rolled[0]:
		EventBus.day_passed.emit(climate.day)
	if rolled[1]:
		EventBus.year_passed.emit(climate.year)

	# --- Bookkeeping ------------------------------------------------------
	_rollup_timer += real_delta
	if _rollup_timer > 0.5:
		_rollup_timer = 0.0
		rollup()
	stats.maybe_sample(tick, entities.population, registry.living_count(),
			stats.avg_temperature, stats.total_vegetation, stats.carnivores)
	return ticks

## Nudges the creature-update budget toward whatever the device can sustain.
## Reacts slowly so it settles instead of oscillating with frame-time noise.
func _tune_budget(real_delta: float) -> void:
	if real_delta > FRAME_BUDGET_HIGH:
		_budget = maxf(float(CREATURE_UPDATES_MIN), _budget * 0.93)
	elif real_delta < FRAME_BUDGET_LOW:
		_budget = minf(float(CREATURE_UPDATES_MAX), _budget * 1.03)

func update_budget() -> int:
	return int(_budget)

## Recomputes the aggregate figures the UI shows. Sampled, not exhaustive:
## a stratified walk over the population and a sparse grid probe.
func rollup() -> void:
	var gen_sum := 0.0
	var speed_sum := 0.0
	var size_sum := 0.0
	var herb := 0
	var carn := 0
	var omni := 0
	var max_gen := 1
	var ids := entities.alive_ids
	var n := ids.size()
	for k in n:
		var c: Creature = entities.creatures[ids[k]]
		if not c.alive:
			continue
		gen_sum += float(c.generation)
		speed_sum += c.dna[DNA.G.SPEED]
		size_sum += c.dna[DNA.G.SIZE]
		max_gen = maxi(max_gen, c.generation)
		if c.diet < 0.38:
			herb += 1
		elif c.diet > 0.62:
			carn += 1
		else:
			omni += 1
	var d: float = maxf(1.0, float(n))
	stats.avg_generation = gen_sum / d
	stats.max_generation = max_gen
	stats.avg_speed_gene = speed_sum / d
	stats.avg_size_gene = size_sum / d
	stats.herbivores = herb
	stats.carnivores = carn
	stats.omnivores = omni

	# Sparse probe of the grid for vegetation and temperature averages.
	var cells := world.w * world.h
	var step: int = maxi(1, int(cells / 2048))
	var veg_sum := 0.0
	var temp_sum := 0.0
	var samples := 0
	var i := (tick * 7) % step
	while i < cells:
		veg_sum += world.veg[i]
		temp_sum += world.temperature[i]
		samples += 1
		i += step
	if samples > 0:
		stats.total_vegetation = veg_sum / float(samples)
		stats.avg_temperature = temp_sum / float(samples)

# --------------------------------------------------------------------------
# Debug / profiling accessors
# --------------------------------------------------------------------------
func last_ticks() -> int:
	return _last_ticks

func last_creature_updates() -> int:
	return _last_updates

func population() -> int:
	return entities.population

func species_count() -> int:
	return registry.living_count()
