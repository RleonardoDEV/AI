extends RefCounted
## The simulation as a whole: scheduling, long-run stability, evolution,
## and save/load round trips.

func test_clock_respects_the_frame_budget(t: TestKit) -> void:
	var sim := Simulation.new()
	sim.build(1717)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	# Even at the highest speed, a frame must never exceed the tick cap.
	sim.set_speed_index(GameConfig.SPEEDS.size() - 1)
	for f in 40:
		var ticks := sim.advance(1.0 / 60.0, view)
		t.at_most(float(ticks), float(GameConfig.MAX_TICKS_PER_FRAME),
				"ticks per frame stay within the cap")
	t.at_least(float(sim.tick), 1.0, "the clock advanced")

func test_pause_freezes_the_world(t: TestKit) -> void:
	var sim := Simulation.new()
	sim.build(1718)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	sim.set_speed_index(0)
	var tick_before := sim.tick
	var pop_before := sim.entities.population
	for f in 30:
		t.eq(sim.advance(1.0 / 60.0, view), 0, "paused frames run no ticks")
	t.eq(sim.tick, tick_before, "tick unchanged while paused")
	t.eq(sim.entities.population, pop_before, "population unchanged while paused")

func test_faster_speeds_advance_more_time(t: TestKit) -> void:
	var slow := Simulation.new()
	slow.build(1719)
	slow.set_speed_index(1)
	var fast := Simulation.new()
	fast.build(1719)
	fast.set_speed_index(5)
	var view := Rect2(0, 0, slow.world.w, slow.world.h)
	for f in 60:
		slow.advance(1.0 / 60.0, view)
		fast.advance(1.0 / 60.0, view)
	t.check(fast.elapsed_sim_time > slow.elapsed_sim_time * 5.0,
			"50x advances far more simulated time than 1x")

func test_population_survives_a_long_run(t: TestKit) -> void:
	var sim := Simulation.new()
	sim.build(24680)
	sim.set_speed_index(5)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	for f in 900:
		sim.advance(1.0 / 60.0, view)
	sim.rollup()
	t.at_least(float(sim.tick), 5000.0, "thousands of ticks executed")
	t.at_least(float(sim.population()), 1.0, "the ecosystem is still alive")
	t.at_least(float(sim.stats.births), 20.0, "creatures reproduced")
	t.at_least(float(sim.species_count()), 1.0, "species remain")
	t.at_most(float(sim.population()), float(GameConfig.MAX_CREATURES), "population cap respected")
	# Bookkeeping must stay internally consistent over a long run.
	var counted := 0
	for k in sim.entities.alive_ids.size():
		if sim.entities.creatures[sim.entities.alive_ids[k]].alive:
			counted += 1
	t.eq(counted, sim.population(), "alive list matches the population counter")
	var species_total := 0
	for s in sim.registry.species:
		species_total += s.population
	t.eq(species_total, sim.population(), "species tallies match the population")

func test_evolution_produces_new_generations(t: TestKit) -> void:
	var sim := Simulation.new()
	sim.build(13579)
	sim.set_speed_index(6)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	for f in 1100:
		sim.advance(1.0 / 60.0, view)
	sim.rollup()
	t.at_least(float(sim.stats.max_generation), 3.0, "several generations have passed")
	t.at_least(float(sim.stats.mutations), 50.0, "mutations occurred")
	t.at_least(float(sim.registry.total_species_created),
			float(SpeciesRegistry.starting_profiles().size()) + 1.0,
			"at least one new species appeared")
	# Descendant species must point at a real ancestor.
	for s in sim.registry.species:
		if s.parent_id >= 0:
			t.not_null(sim.registry.get_species(s.parent_id), "ancestor exists")

func test_hotspot_lands_inside_the_world(t: TestKit) -> void:
	var sim := Simulation.new()
	sim.build(2244)
	var p := sim.population_hotspot()
	t.between(p.x, 0.0, float(sim.world.w), "hotspot x inside world")
	t.between(p.y, 0.0, float(sim.world.h), "hotspot y inside world")

func test_save_and_load_round_trip(t: TestKit) -> void:
	var sim := Simulation.new()
	sim.build(31337)
	sim.set_speed_index(4)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	for f in 200:
		sim.advance(1.0 / 60.0, view)
	# Leave a permanent mark so the delta has something to carry.
	var centre := Vector2(float(sim.world.w) * 0.5, float(sim.world.h) * 0.5)
	WorldTools.meteor(sim.ctx, centre, 1.0)
	WorldTools.raise_rock(sim.ctx, centre + Vector2(30.0, 0.0), 5.0)
	sim.rollup()

	var pop := sim.population()
	var species := sim.species_count()
	var tick := sim.tick
	var year := sim.climate.year
	var created := sim.registry.total_species_created
	var flora := sim.flora.count
	var delta_size := sim.world.modified.size()
	var sample_idx := PackedInt32Array()
	var sample_terrain := PackedByteArray()
	for k in mini(400, sim.world.modified.size()):
		var i: int = sim.world.modified[k]
		sample_idx.append(i)
		sample_terrain.append(sim.world.terrain[i])

	t.check(SaveManager.save_world(sim), "world saved")
	t.check(SaveManager.has_save(), "save file exists")

	var loaded := SaveManager.load_world()
	t.not_null(loaded, "world loaded")
	if loaded == null:
		return
	t.eq(loaded.world_seed, 31337, "seed restored")
	t.eq(loaded.population(), pop, "population restored")
	t.eq(loaded.species_count(), species, "living species restored")
	t.eq(loaded.tick, tick, "tick restored")
	t.eq(loaded.climate.year, year, "calendar restored")
	t.eq(loaded.registry.total_species_created, created, "species history restored")
	t.eq(loaded.flora.count, flora, "flora restored")
	t.at_least(float(loaded.world.modified.size()), float(delta_size) * 0.99,
			"terrain delta restored")
	var mismatch := 0
	for k in sample_idx.size():
		if loaded.world.terrain[sample_idx[k]] != sample_terrain[k]:
			mismatch += 1
	t.eq(mismatch, 0, "every changed cell came back identical")
	# The restored world must keep running.
	for f in 60:
		loaded.advance(1.0 / 60.0, view)
	t.at_least(float(loaded.population()), 1.0, "restored world keeps simulating")

func test_saved_creatures_keep_their_genomes(t: TestKit) -> void:
	var sim := Simulation.new()
	sim.build(4711)
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	for f in 60:
		sim.advance(1.0 / 60.0, view)
	# Record a fingerprint of the population's genetics.
	var sum_before := 0.0
	for k in sim.entities.alive_ids.size():
		var c: Creature = sim.entities.creatures[sim.entities.alive_ids[k]]
		if c.alive:
			for i in DNA.NUM_GENES:
				sum_before += c.dna[i]
	SaveManager.save_world(sim)
	var loaded := SaveManager.load_world()
	if loaded == null:
		return
	var sum_after := 0.0
	for k in loaded.entities.alive_ids.size():
		var c2: Creature = loaded.entities.creatures[loaded.entities.alive_ids[k]]
		if c2.alive:
			for i in DNA.NUM_GENES:
				sum_after += c2.dna[i]
	t.approx(sum_after, sum_before, maxf(0.5, absf(sum_before) * 0.001),
			"genomes survive a save/load cycle")
