class_name Brain
extends RefCounted
## Utility-based decision making plus the movement that carries each decision
## out. Behaviour is scored every update from needs and context; the winning
## behaviour gets a small hysteresis bonus so creatures commit to an action
## instead of twitching between two near-equal options.
##
## Emergent results this produces in practice: herds forming and grazing a
## patch down before moving on, predators cutting out stragglers, prey
## abandoning water when a predator camps it, whole populations migrating when
## a cold snap pushes them out of their thermal band, and panicked mixed-species
## stampedes away from a fire front.

const HYSTERESIS: float = 0.14
const REACH: float = 1.15

static func think_and_act(ctx: SimContext, c: Creature, dt: float) -> void:
	var world := ctx.world
	# Positions are clamped inside the world by _steer, so the index needs no
	# bounds work here — this is the hottest line in the simulation.
	var cell: int = int(c.pos.y) * world.w + int(c.pos.x)

	# ---------------------------------------------------------------- sensing
	c.scan_countdown -= 1
	if c.scan_countdown <= 0:
		Perception.scan(ctx, c)
		c.scan_countdown = Creature.SCAN_EVERY
		if Perception.threat_id >= 0:
			c.mem_threat = Perception.threat_pos
			c.mem_threat_age = 0.0
	c.mem_threat_age += dt

	var fire_pos := Vector2(-1, -1)
	if not world.burning_cells.is_empty():
		if c.scan_countdown >= Creature.SCAN_EVERY:
			c.mem_fire = Perception.find_fire(ctx, c, 18.0)
		fire_pos = c.mem_fire
	else:
		c.mem_fire = Vector2(-1, -1)

	# ---------------------------------------------------------------- scoring
	# Thirst and hunger grow super-linearly: an animal at 0.9 thirst does
	# little else, but a mildly thirsty one keeps foraging.
	var thirst_s := c.thirst * c.thirst * 1.9
	var hunger_s := c.hunger * c.hunger * 1.45
	var fear_s := 0.0
	if Perception.threat_id >= 0:
		var prox: float = clampf(1.0 - Perception.threat_dist / maxf(1.0, c.vision), 0.0, 1.0)
		fear_s = (0.45 + c.fear_gene) * 2.4 * prox
	elif c.mem_threat_age < 3.0 and c.mem_threat.x >= 0.0:
		fear_s = (0.3 + c.fear_gene) * 0.75 * (1.0 - c.mem_threat_age / 3.0)
	var fire_s := 0.0
	if fire_pos.x >= 0.0:
		var fd := c.pos.distance_to(fire_pos)
		fire_s = clampf(2.9 * (1.0 - fd / 18.0), 0.0, 3.2)
	var hunt_s := 0.0
	# A fed predator does not hunt. Without this gate, carnivores killed far
	# more than they could eat and drove their own prey — and then themselves —
	# to extinction within a couple of simulated years.
	if Perception.prey_id >= 0 and c.hunger > 0.12:
		if c.is_carnivore():
			hunt_s = (0.1 + c.hunger * 1.5) * (0.4 + c.aggression) * 1.8
		elif c.diet > 0.38:
			hunt_s = (c.hunger - 0.25) * (0.25 + c.aggression) * 1.3
	var mate_s := 0.0
	if Perception.mate_id >= 0 and c.energy > 0.38:
		# Courtship never outranks survival: a starving or parched animal
		# stops looking for a mate. (Without this factor, full reproductive
		# drive beat hunger and thirst outright and populations starved.)
		var satiety: float = 1.0 - maxf(c.hunger, c.thirst)
		mate_s = c.repro_drive * 1.75 * clampf(satiety, 0.0, 1.0)
	var rest_s := 0.0
	if c.energy < 0.34:
		rest_s = (0.34 - c.energy) * 3.4
	var comfort_err := absf(world.temperature[cell] - c.temp_pref)
	var migrate_s := 0.0
	if comfort_err > 9.0:
		migrate_s = clampf((comfort_err - 9.0) * 0.1, 0.0, 1.25)

	# A plant eater standing on grass just eats, rather than "seeking food".
	var on_food: bool = world.veg[cell] > 0.06 and c.diet < 0.66
	var on_water: bool = world.is_drinkable(cell)

	# Scored inline rather than through a candidate array: this runs for every
	# creature on every update, and building an Array here cost more than the
	# rest of the decision put together.
	var cur := c.state
	var best := Creature.State.WANDER
	var best_score: float = 0.22 + sin(c.wander_phase) * 0.03
	if cur == Creature.State.WANDER:
		best_score += HYSTERESIS

	var sc: float = fire_s + (HYSTERESIS if cur == Creature.State.FLEE_FIRE else 0.0)
	if sc > best_score:
		best_score = sc
		best = Creature.State.FLEE_FIRE
	sc = fear_s + (HYSTERESIS if cur == Creature.State.FLEE else 0.0)
	if sc > best_score:
		best_score = sc
		best = Creature.State.FLEE
	var water_state: int = Creature.State.DRINK if on_water else Creature.State.SEEK_WATER
	sc = thirst_s + (HYSTERESIS if cur == water_state else 0.0)
	if sc > best_score:
		best_score = sc
		best = water_state
	var food_state: int = Creature.State.EAT if on_food else Creature.State.SEEK_FOOD
	sc = hunger_s + (HYSTERESIS if cur == food_state else 0.0)
	if sc > best_score:
		best_score = sc
		best = food_state
	sc = hunt_s + (HYSTERESIS if cur == Creature.State.HUNT else 0.0)
	if sc > best_score:
		best_score = sc
		best = Creature.State.HUNT
	sc = mate_s + (HYSTERESIS if cur == Creature.State.MATE else 0.0)
	if sc > best_score:
		best_score = sc
		best = Creature.State.MATE
	sc = rest_s + (HYSTERESIS if cur == Creature.State.REST else 0.0)
	if sc > best_score:
		best_score = sc
		best = Creature.State.REST
	sc = migrate_s + (HYSTERESIS if cur == Creature.State.MIGRATE else 0.0)
	if sc > best_score:
		best_score = sc
		best = Creature.State.MIGRATE

	if best != c.state:
		c.state = best
		c.state_timer = 0.0
		c.search_countdown = 0
	c.state_timer += dt

	# ---------------------------------------------------------------- acting
	var desired := Vector2.ZERO
	var urgency := 0.55

	match c.state:
		Creature.State.FLEE_FIRE:
			if fire_pos.x >= 0.0:
				desired = (c.pos - fire_pos).normalized()
			urgency = 1.15
		Creature.State.FLEE:
			var from := Perception.threat_pos if Perception.threat_id >= 0 else c.mem_threat
			if from.x >= 0.0:
				desired = (c.pos - from).normalized()
				# Break line of flight slightly so chases curve.
				desired = desired.rotated(sin(c.wander_phase * 2.3) * 0.35)
			urgency = 1.0 + c.stamina * 0.18
		Creature.State.SEEK_WATER:
			c.search_countdown -= 1
			if c.search_countdown <= 0:
				var wp := Perception.find_water(ctx, c)
				c.search_countdown = Creature.SEARCH_EVERY
				if wp.x >= 0.0:
					c.target_pos = wp
					c.mem_water = wp
			desired = _toward(c, c.target_pos)
			urgency = 0.55 + c.thirst * 0.5
		Creature.State.DRINK:
			c.thirst = maxf(0.0, c.thirst - dt * 0.85)
			c.mem_water = c.pos
			desired = Vector2.ZERO
			urgency = 0.0
		Creature.State.SEEK_FOOD:
			c.search_countdown -= 1
			if c.search_countdown <= 0:
				var fp := Perception.find_forage(ctx, c)
				c.search_countdown = Creature.SEARCH_EVERY
				if fp.x >= 0.0:
					c.target_pos = fp
					c.mem_food = fp
				elif Perception.prey_id >= 0:
					c.target_pos = Perception.prey_pos
			desired = _toward(c, c.target_pos)
			urgency = 0.5 + c.hunger * 0.55
		Creature.State.EAT:
			var eaten := world.consume_veg(cell, dt * (0.30 + c.body_size * 0.35))
			if eaten > 0.0:
				c.hunger = maxf(0.0, c.hunger - eaten * 1.75)
				c.energy = minf(1.0, c.energy + eaten * 1.15)
				c.mem_food = c.pos
			urgency = 0.0
		Creature.State.HUNT:
			if Perception.prey_id >= 0:
				var prey: Creature = ctx.entities.creatures[Perception.prey_id]
				if prey.alive:
					c.target_pos = prey.pos
					desired = _toward(c, prey.pos)
					urgency = 1.0 + c.aggression * 0.25
					# At high simulation speeds a single update can carry a
					# predator straight past its prey, so the strike window
					# covers the whole step, not just the end of it.
					var reach: float = REACH + c.body_size * 0.5 + minf(c.vel.length() * dt * 0.35, 1.8)
					if Perception.prey_dist < reach:
						_attack(ctx, c, prey, dt)
			else:
				desired = _toward(c, c.target_pos)
				urgency = 0.8
		Creature.State.MATE:
			if Perception.mate_id >= 0:
				var mate: Creature = ctx.entities.creatures[Perception.mate_id]
				if mate.alive:
					desired = _toward(c, mate.pos)
					urgency = 0.7
					var pair_reach: float = 1.6 + minf(c.vel.length() * dt * 0.5, 2.2)
					if c.pos.distance_squared_to(mate.pos) < pair_reach * pair_reach:
						ctx.entities.try_reproduce(ctx, c, mate)
		Creature.State.REST:
			desired = Vector2.ZERO
			urgency = 0.0
			c.energy = minf(1.0, c.energy + dt * 0.145 * (0.5 + c.stamina * 0.5))
		Creature.State.MIGRATE:
			c.search_countdown -= 1
			if c.search_countdown <= 0:
				var cp := Perception.find_comfort(ctx, c)
				c.search_countdown = Creature.SEARCH_EVERY * 2
				if cp.x >= 0.0:
					c.target_pos = cp
			desired = _toward(c, c.target_pos)
			urgency = 0.62
		_:
			# Wander: slowly turning heading, biased back toward home range.
			c.wander_phase += dt * (0.55 + c.max_speed * 0.14)
			var drift := Vector2.from_angle(c.wander_phase * 1.7 + float(c.id) * 0.37)
			var homeward := (c.mem_home - c.pos)
			if homeward.length() > 34.0:
				drift = drift.lerp(homeward.normalized(), 0.55)
			desired = drift.normalized()
			urgency = 0.34

	# ------------------------------------------------------- social steering
	if Perception.flock_count > 0 and c.social > 0.15:
		var cohesion := (Perception.flock_center - c.pos)
		if cohesion.length() > 2.5:
			desired += cohesion.normalized() * c.social * 0.45
		desired += Perception.flock_vel.normalized() * c.social * 0.22
	if Perception.crowding > 0:
		desired += Perception.separation.normalized() * 0.7

	_steer(ctx, c, desired, urgency, dt)

# --------------------------------------------------------------------------
# Movement
# --------------------------------------------------------------------------
static func _toward(c: Creature, p: Vector2) -> Vector2:
	if p.x < 0.0:
		return Vector2.from_angle(c.wander_phase)
	var d := p - c.pos
	if d.length_squared() < 0.04:
		return Vector2.ZERO
	return d.normalized()

## Applies terrain preference, water avoidance, acceleration and the energy
## cost of moving. Movement is the main energy sink, which is what makes speed
## genes a real trade-off rather than a free win.
static func _steer(ctx: SimContext, c: Creature, desired: Vector2, urgency: float, dt: float) -> void:
	var world := ctx.world
	if desired.length_squared() > 0.0001:
		desired = desired.normalized()
		# Avoid terrain the creature cannot handle. Land animals look further
		# ahead than they can stop in, which is what stops herds walking into
		# the sea while fleeing.
		var look: float = 1.6 + c.vel.length() * 0.35
		var ahead := c.pos + desired * look
		var ai := world.idx_at(ahead)
		var at: int = world.terrain[ai]
		var wet := Terrain.is_water(at)
		if wet and c.aquatic < 0.55:
			desired = _deflect(world, c, desired, true)
			# If already standing in water, head for the nearest dry ground.
			if Terrain.is_water(world.terrain[int(c.pos.y) * world.w + int(c.pos.x)]):
				var escape := _nearest_dry(world, c)
				if escape.x >= 0.0:
					desired = (escape - c.pos).normalized()
		elif not wet and c.aquatic > 0.88:
			desired = _deflect(world, c, desired, false)
		elif at == Terrain.T.LAVA:
			desired = -desired
		elif world.fire[ai] > 0.05 and c.state != Creature.State.FLEE_FIRE:
			desired = _deflect(world, c, desired, wet)

	var here: int = world.terrain[int(c.pos.y) * world.w + int(c.pos.x)]
	var terrain_mul := 1.0 / Terrain.MOVE_COST[here]
	if Terrain.is_water(here):
		terrain_mul *= 0.45 + c.aquatic * 1.05
	var sprint: float = 1.0 if urgency < 0.9 else (1.0 + 0.4 * clampf(c.stamina, 0.0, 2.0))
	var target_vel := desired * c.max_speed * urgency * terrain_mul * sprint
	var accel: float = 5.5 + c.max_speed * 1.6
	c.vel = c.vel.lerp(target_vel, clampf(dt * accel, 0.0, 1.0))

	var step := c.vel * dt
	var np := c.pos + step
	np.x = clampf(np.x, 0.6, float(world.w) - 1.6)
	np.y = clampf(np.y, 0.6, float(world.h) - 1.6)
	# Impassable terrain is a hard constraint, not a penalty. Steering alone
	# let fleeing herds run straight into the sea and drown en masse; blocking
	# the move instead makes them run *along* the shore, which is both correct
	# and far better behaviour to watch. Axis-separated retries let them slide
	# along a coastline rather than sticking to it.
	if _blocked(world, c, np):
		var slide_x := Vector2(np.x, c.pos.y)
		var slide_y := Vector2(c.pos.x, np.y)
		if not _blocked(world, c, slide_x):
			np = slide_x
			c.vel.y *= 0.25
		elif not _blocked(world, c, slide_y):
			np = slide_y
			c.vel.x *= 0.25
		else:
			np = c.pos
			c.vel *= -0.2
	c.pos = np

	# Energy: moving costs more the faster and heavier you are.
	var spd := c.vel.length()
	if spd > 0.05:
		# Linear-ish in speed. A quadratic term here looked physical but made
		# fast predators bankrupt themselves in a single chase: they spent
		# their whole lives below the energy needed to breed, and every
		# carnivore lineage went extinct within a few simulated years.
		var cost := (0.004 + spd * 0.0035 * (0.5 + c.body_size * 0.5)) * dt
		c.energy = maxf(0.0, c.energy - cost / maxf(0.4, c.stamina * 0.6 + 0.5))
		c.anim_t += spd * dt * 2.6
		# 8-direction facing by octant comparison (atan2 was showing up in the
		# profile for something that is three branches of work).
		var vx := c.vel.x
		var vy := c.vel.y
		var ax := absf(vx)
		var ay := absf(vy)
		var oct: int
		if ax > ay:
			oct = 0 if vx > 0.0 else 4
			if ay > ax * 0.4142:
				oct = (1 if vy > 0.0 else 7) if vx > 0.0 else (3 if vy > 0.0 else 5)
		else:
			oct = 2 if vy > 0.0 else 6
			if ax > ay * 0.4142:
				oct = (1 if vx > 0.0 else 3) if vy > 0.0 else (7 if vx > 0.0 else 5)
		c.facing = oct

## True when `p` is terrain this creature cannot cross. Shallow water is
## passable by everything, which keeps shorelines walkable.
static func _blocked(world: WorldData, c: Creature, p: Vector2) -> bool:
	var t: int = world.terrain[int(p.y) * world.w + int(p.x)]
	if t == Terrain.T.LAVA:
		return true
	if t <= Terrain.T.WATER:
		return c.aquatic < 0.5
	if not Terrain.is_water(t):
		return c.aquatic > 0.92
	return false

## Nearest walkable cell for a creature caught in water, or (-1,-1).
static func _nearest_dry(world: WorldData, c: Creature) -> Vector2:
	for r in [2, 4, 7, 11]:
		for k in 8:
			var d := Vector2.from_angle(float(k) * TAU / 8.0) * float(r)
			var p := c.pos + d
			if p.x < 1.0 or p.y < 1.0 or p.x >= float(world.w) - 1.0 or p.y >= float(world.h) - 1.0:
				continue
			var t: int = world.terrain[world.idx_at(p)]
			if not Terrain.is_water(t) and t != Terrain.T.LAVA:
				return p
	return Vector2(-1, -1)

## Picks the nearest probe direction that keeps the creature on valid ground.
static func _deflect(world: WorldData, c: Creature, desired: Vector2, avoid_water: bool) -> Vector2:
	for turn in [0.7, -0.7, 1.4, -1.4, 2.2, -2.2, PI]:
		var d := desired.rotated(turn)
		var p := c.pos + d * 1.8
		var i := world.idx_at(p)
		var wet := Terrain.is_water(world.terrain[i])
		if world.terrain[i] == Terrain.T.LAVA:
			continue
		if avoid_water and not wet:
			return d
		if not avoid_water and wet:
			return d
	return -desired

# --------------------------------------------------------------------------
# Combat
# --------------------------------------------------------------------------
static func _attack(ctx: SimContext, c: Creature, prey: Creature, dt: float) -> void:
	c.attack_cooldown -= dt
	if c.attack_cooldown > 0.0:
		return
	c.attack_cooldown = 0.8
	var dmg := c.bite_power() * (0.6 + ctx.rng.randf() * 0.6) * 1.05
	# Bigger prey resists.
	dmg /= maxf(0.35, prey.body_size * 0.75 + 0.4)
	prey.health -= dmg
	prey.fear = 1.0
	prey.mem_threat = c.pos
	prey.mem_threat_age = 0.0
	ctx.stats.note_attack()
	if prey.health <= 0.0:
		var meal := prey.meat_value()
		c.hunger = maxf(0.0, c.hunger - meal * 0.85)
		c.energy = minf(1.0, c.energy + meal * 0.72)
		c.repro_drive = minf(1.0, c.repro_drive + 0.08)
		ctx.entities.kill(ctx, prey, Creature.Cause.PREDATION)
