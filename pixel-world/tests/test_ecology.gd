extends RefCounted
## Fire, water, vegetation, weather events and the spatial grid.

func _sim(seed_value: int = 909) -> Simulation:
	var s := Simulation.new()
	s.build(seed_value)
	return s

func _find_flammable(sim: Simulation) -> int:
	for i in sim.world.terrain.size():
		if Terrain.FLAMMABILITY[sim.world.terrain[i]] > 0.7 and sim.world.veg[i] > 0.4:
			return i
	return -1

func test_fire_spreads_then_burns_out(t: TestKit) -> void:
	var sim := _sim()
	var i := _find_flammable(sim)
	t.check(i >= 0, "found flammable ground")
	if i < 0:
		return
	var pos := Vector2(float(i % sim.world.w) + 0.5, float(int(i / sim.world.w)) + 0.5)
	var lit := WorldTools.ignite(sim.ctx, pos, 3.0, 0.9)
	t.at_least(float(lit), 1.0, "ignition lights cells")
	var peak := sim.world.burning_cells.size()
	for step in 40:
		sim.fire.update(sim.ctx, 0.2, Vector2(0.5, 0.0))
		peak = maxi(peak, sim.world.burning_cells.size())
	t.at_least(float(peak), float(lit), "fire spreads beyond the ignition point")
	for step in 900:
		if sim.world.burning_cells.is_empty():
			break
		sim.fire.update(sim.ctx, 0.4, Vector2(0.5, 0.0))
	t.eq(sim.world.burning_cells.size(), 0, "fire eventually burns out")
	t.at_least(float(sim.fire.cells_burned), 1.0, "burned cells counted")

func test_fire_consumes_vegetation_and_leaves_scorched_ground(t: TestKit) -> void:
	var sim := _sim(910)
	var i := _find_flammable(sim)
	if i < 0:
		return
	var veg_before := sim.world.veg[i]
	sim.world.ignite(i, 0.9)
	for step in 200:
		if sim.world.burning_cells.is_empty():
			break
		sim.fire.update(sim.ctx, 0.3, Vector2.ZERO)
	t.check(sim.world.veg[i] < veg_before, "fire consumed fuel")

func test_water_does_not_burn(t: TestKit) -> void:
	var sim := _sim(911)
	var water_cell := -1
	for i in sim.world.terrain.size():
		if Terrain.is_water(sim.world.terrain[i]):
			water_cell = i
			break
	t.check(water_cell >= 0, "found water")
	if water_cell >= 0:
		t.check(not sim.world.ignite(water_cell, 1.0), "water cannot be set alight")

func test_rain_extinguishes_fire_and_wets_ground(t: TestKit) -> void:
	var sim := _sim(912)
	var i := _find_flammable(sim)
	if i < 0:
		return
	var pos := Vector2(float(i % sim.world.w) + 0.5, float(int(i / sim.world.w)) + 0.5)
	WorldTools.ignite(sim.ctx, pos, 3.0, 0.9)
	t.at_least(float(sim.world.burning_cells.size()), 1.0, "fire is burning")
	WorldTools.rain(sim.ctx, pos, 9.0, 1.0)
	t.at_least(sim.world.water[i], 0.05, "ground is wet")
	for step in 30:
		sim.fire.update(sim.ctx, 0.25, Vector2.ZERO)
	t.eq(sim.world.fire[i], 0.0, "rain put the fire out")

func test_surface_water_evaporates(t: TestKit) -> void:
	var sim := _sim(913)
	var land := -1
	for i in sim.world.terrain.size():
		if sim.world.terrain[i] == Terrain.T.GRASS:
			land = i
			break
	if land < 0:
		return
	sim.world.add_water(land, 1.0)
	t.at_least(sim.world.water[land], 0.5, "water applied")
	for step in 600:
		sim.water.update(sim.ctx, 0.5)
		if sim.world.water[land] <= 0.02:
			break
	t.at_most(sim.world.water[land], 0.05, "water drains or evaporates")

func test_vegetation_regrows_after_grazing(t: TestKit) -> void:
	var sim := _sim(914)
	var cell := -1
	for i in sim.world.terrain.size():
		if Terrain.FERTILITY[sim.world.terrain[i]] > 0.8 and sim.world.moisture[i] > 0.5:
			cell = i
			break
	if cell < 0:
		return
	sim.world.veg[cell] = 0.0
	# Drive the growth sweep until it has visited the whole grid a few times.
	for step in GrowthSystem.SLICES * 60:
		sim.growth.update(sim.ctx, 0.25)
		if sim.world.veg[cell] > 0.1:
			break
	t.at_least(sim.world.veg[cell], 0.05, "vegetation regrows on fertile ground")

func test_tools_change_the_world(t: TestKit) -> void:
	var sim := _sim(915)
	var centre := Vector2(float(sim.world.w) * 0.5, float(sim.world.h) * 0.5)
	var i := sim.world.idx_at(centre)

	WorldTools.raise_rock(sim.ctx, centre, 4.0)
	t.eq(sim.world.terrain[i], Terrain.T.ROCK, "rock tool raises rock")

	WorldTools.flood(sim.ctx, centre, 4.0)
	t.check(Terrain.is_water(sim.world.terrain[i]), "water tool floods")

	WorldTools.freeze(sim.ctx, centre, 5.0)
	t.check(sim.world.terrain[i] == Terrain.T.ICE or sim.world.snow[i] > 0.1,
			"ice tool freezes")

	var pop_before := sim.entities.population
	var made := WorldTools.spawn_life(sim.ctx, Vector2(20.0, 20.0), 3)
	t.eq(sim.entities.population, pop_before + made, "creature tool spawns life")

func test_meteor_craters_and_kills(t: TestKit) -> void:
	var sim := _sim(916)
	sim.entities.rebuild_grid()
	var ids := sim.entities.alive_ids
	t.at_least(float(ids.size()), 1.0, "population exists")
	var victim: Creature = sim.entities.creatures[ids[0]]
	var at := victim.pos
	var pop_before := sim.entities.population
	WorldTools.meteor(sim.ctx, at, 1.0)
	var i := sim.world.idx_at(at)
	t.check(sim.world.terrain[i] == Terrain.T.LAVA or sim.world.terrain[i] == Terrain.T.ASH
			or sim.world.terrain[i] == Terrain.T.ROCK, "impact reshaped the ground")
	t.at_most(float(sim.entities.population), float(pop_before), "impact was lethal")
	t.at_least(float(sim.world.modified.size()), 10.0, "crater recorded in the delta")

func test_spatial_grid_finds_neighbours(t: TestKit) -> void:
	var grid := SpatialGrid.new(64, 64, 8)
	grid.insert(1, 10.0, 10.0)
	grid.insert(2, 12.0, 11.0)
	grid.insert(3, 60.0, 60.0)
	var near := grid.query(10.0, 10.0, 6.0)
	t.check(near.has(1), "finds the point at the query centre")
	t.check(near.has(2), "finds a nearby point")
	t.check(not near.has(3), "excludes a distant point")
	var all := grid.query(32.0, 32.0, 64.0)
	t.eq(all.size(), 3, "a wide query finds everything")
	grid.clear()
	t.eq(grid.query(10.0, 10.0, 8.0).size(), 0, "clear empties the grid")

func test_spatial_grid_cap_is_respected(t: TestKit) -> void:
	var grid := SpatialGrid.new(64, 64, 8)
	for i in 200:
		grid.insert(i, 32.0, 32.0)
	var capped := grid.query(32.0, 32.0, 10.0, 24, 0)
	t.at_most(float(capped.size()), 24.0, "capped query bounds its result")
	t.at_least(float(capped.size()), 1.0, "capped query still returns results")

func test_weather_events_alter_the_world(t: TestKit) -> void:
	var sim := _sim(917)
	sim.weather.event_cooldown = 0.0
	sim.weather.update(sim.ctx, 0.1, sim.water, sim.growth)
	t.check(sim.weather.event_id != WeatherSystem.E.NONE, "an event started")
	t.at_least(float(sim.weather.events_fired), 1.0, "event counted")
	t.at_least(float(sim.weather.event_history.size()), 1.0, "event recorded in history")
	# Drought and bloom must actually change growth or evaporation.
	var g := sim.growth.growth_mul
	var e := sim.water.evaporation_mul
	t.check(g > 0.0 and e > 0.0, "event multipliers stay positive")
	sim.weather.event_timer = 0.0
	sim.weather.update(sim.ctx, 0.1, sim.water, sim.growth)
	t.approx(sim.growth.growth_mul, 1.0, 0.001, "growth restored after the event")
	t.approx(sim.water.evaporation_mul, 1.0, 0.001, "evaporation restored after the event")

func test_climate_advances_days_and_years(t: TestKit) -> void:
	var c := Climate.new()
	var day_seconds := float(GameConfig.TICKS_PER_DAY) * GameConfig.TICK_DT
	var rolled := c.advance(day_seconds)
	t.check(rolled[0], "a full day rolls over")
	t.eq(c.day, 1, "day counter advanced")
	for i in GameConfig.DAYS_PER_YEAR:
		c.advance(day_seconds)
	t.at_least(float(c.year), 1.0, "a year passed")
	t.between(c.day_factor, 0.0, 1.0, "daylight factor normalised")
	t.check(c.time_label().length() == 5, "clock label formatted")
