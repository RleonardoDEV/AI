extends RefCounted
## Creature vitals, phenotype, movement, death and reproduction.

func _sim(seed_value: int = 555) -> Simulation:
	var s := Simulation.new()
	s.build(seed_value)
	return s

func test_phenotype_follows_dna(t: TestKit) -> void:
	var sim := _sim()
	var ids := sim.entities.alive_ids
	t.at_least(float(ids.size()), 20.0, "world seeds a starting population")
	for k in mini(30, ids.size()):
		var c: Creature = sim.entities.creatures[ids[k]]
		t.approx(c.max_speed, c.dna[DNA.G.SPEED] * 5.2 + 0.7, 0.001, "speed derived from DNA")
		t.approx(c.vision, c.dna[DNA.G.VISION], 0.001, "vision derived from DNA")
		t.approx(c.diet, c.dna[DNA.G.DIET], 0.001, "diet derived from DNA")
		t.between(c.health, 0.0, 1.0, "health normalised")
		t.between(c.draw_scale(), 0.05, 3.0, "draw scale sane")

func test_newborns_are_smaller_than_adults(t: TestKit) -> void:
	var sim := _sim(556)
	var ids := sim.entities.alive_ids
	var c: Creature = sim.entities.creatures[ids[0]]
	c.age = 0.0
	var young := c.draw_scale()
	c.age = c.lifespan * 0.9
	var grown := c.draw_scale()
	t.check(young < grown, "juveniles draw smaller than adults")
	t.check(not c.is_adult() or c.age >= c.maturity(), "maturity threshold consistent")

func test_needs_increase_over_time(t: TestKit) -> void:
	var sim := _sim(557)
	var c: Creature = sim.entities.creatures[sim.entities.alive_ids[0]]
	c.hunger = 0.1
	c.thirst = 0.1
	c.state = Creature.State.REST
	var h0 := c.hunger
	var th0 := c.thirst
	var a0 := c.age
	for i in 40:
		sim.entities._update_one(sim.ctx, c, 0.2)
	t.at_least(c.hunger, h0, "hunger rises")
	t.at_least(c.thirst, th0, "thirst rises")
	t.at_least(c.age, a0, "creatures age")

func test_starvation_and_thirst_kill(t: TestKit) -> void:
	var sim := _sim(558)
	var c: Creature = sim.entities.creatures[sim.entities.alive_ids[0]]
	c.hunger = 1.0
	c.thirst = 1.0
	c.health = 0.05
	var pop_before := sim.entities.population
	for i in 60:
		if not c.alive:
			break
		sim.entities._update_one(sim.ctx, c, 0.3)
	t.check(not c.alive, "a creature with no food or water dies")
	t.eq(sim.entities.population, pop_before - 1, "population decremented")
	t.at_least(float(sim.stats.deaths), 1.0, "death recorded in stats")

func test_old_age_kills(t: TestKit) -> void:
	var sim := _sim(559)
	var c: Creature = sim.entities.creatures[sim.entities.alive_ids[0]]
	c.age = c.lifespan * 1.4
	c.hunger = 0.0
	c.thirst = 0.0
	c.energy = 1.0
	for i in 400:
		if not c.alive:
			break
		sim.entities._update_one(sim.ctx, c, 0.4)
	t.check(not c.alive, "creatures die of old age")

func test_creatures_stay_inside_the_world(t: TestKit) -> void:
	var sim := _sim(560)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	for f in 120:
		sim.advance(1.0 / 60.0, view)
	var ids := sim.entities.alive_ids
	for k in ids.size():
		var c: Creature = sim.entities.creatures[ids[k]]
		if not c.alive:
			continue
		t.between(c.pos.x, 0.0, float(sim.world.w), "x inside world")
		t.between(c.pos.y, 0.0, float(sim.world.h), "y inside world")

func test_land_animals_do_not_enter_deep_water(t: TestKit) -> void:
	var sim := _sim(561)
	sim.set_speed_index(4)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	for f in 240:
		sim.advance(1.0 / 60.0, view)
	var offenders := 0
	var ids := sim.entities.alive_ids
	for k in ids.size():
		var c: Creature = sim.entities.creatures[ids[k]]
		if not c.alive or c.aquatic >= 0.5:
			continue
		if sim.world.terrain[sim.world.idx_at(c.pos)] <= Terrain.T.WATER:
			offenders += 1
	t.eq(offenders, 0, "non-swimmers never stand in open water")

func test_reproduction_produces_a_mutated_child(t: TestKit) -> void:
	var sim := _sim(562)
	var ids := sim.entities.alive_ids
	# Find two adults of the same species.
	var a: Creature = null
	var b: Creature = null
	for k in ids.size():
		var c: Creature = sim.entities.creatures[ids[k]]
		if not c.alive:
			continue
		c.age = maxf(c.age, c.maturity() * 1.2)
		c.energy = 0.95
		c.breed_cooldown = 0.0
		c.repro_drive = 1.0
		if a == null:
			a = c
		elif b == null and c.species_id == a.species_id:
			b = c
	t.not_null(a, "found a first parent")
	t.not_null(b, "found a mate of the same species")
	if a == null or b == null:
		return
	b.pos = a.pos
	var before := sim.entities.population
	var births_before := sim.stats.births
	var child := sim.entities.try_reproduce(sim.ctx, a, b)
	t.not_null(child, "reproduction succeeded")
	if child == null:
		return
	t.eq(sim.entities.population, before + 1, "population grew")
	t.eq(sim.stats.births, births_before + 1, "birth recorded")
	t.eq(child.generation, maxi(a.generation, b.generation) + 1, "generation advanced")
	t.check(child.energy > 0.0, "child starts with energy")
	t.check(a.repro_drive == 0.0, "parent drive reset")
	t.check(a.breed_cooldown > 0.0, "parent enters cooldown")
	for i in DNA.NUM_GENES:
		t.between(child.dna[i], DNA.MIN[i], DNA.MAX[i], "child gene in range")
	# Inherited memory is what keeps descendants viable.
	t.check(child.mem_home == a.pos, "child remembers its birthplace")

func test_reproduction_requires_energy_and_maturity(t: TestKit) -> void:
	var sim := _sim(563)
	var ids := sim.entities.alive_ids
	var a: Creature = sim.entities.creatures[ids[0]]
	var b: Creature = null
	for k in range(1, ids.size()):
		var c: Creature = sim.entities.creatures[ids[k]]
		if c.alive and c.species_id == a.species_id:
			b = c
			break
	if b == null:
		return
	a.age = 0.0
	b.age = 0.0
	a.energy = 1.0
	b.energy = 1.0
	a.breed_cooldown = 0.0
	b.breed_cooldown = 0.0
	t.check(sim.entities.try_reproduce(sim.ctx, a, b) == null, "juveniles cannot breed")
	a.age = a.maturity() * 2.0
	b.age = b.maturity() * 2.0
	a.energy = 0.05
	b.energy = 0.05
	t.check(sim.entities.try_reproduce(sim.ctx, a, b) == null, "exhausted adults cannot breed")

func test_dead_creatures_are_recycled(t: TestKit) -> void:
	var sim := _sim(564)
	var before_free := sim.entities.free_ids.size()
	var c: Creature = sim.entities.creatures[sim.entities.alive_ids[0]]
	sim.entities.kill(sim.ctx, c, Creature.Cause.DIVINE)
	sim.entities.reap()
	t.eq(sim.entities.free_ids.size(), before_free + 1, "id returned to the pool")
	t.check(not sim.entities.alive_ids.has(c.id), "id removed from the alive list")
	t.at_least(float(sim.entities.corpse_count), 1.0, "a corpse was left behind")
