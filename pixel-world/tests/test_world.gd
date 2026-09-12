extends RefCounted
## Procedural generation: determinism, coverage, structure.

func test_same_seed_produces_identical_world(t: TestKit) -> void:
	var a := WorldData.new()
	var b := WorldData.new()
	WorldGen.generate(a, 20250912)
	WorldGen.generate(b, 20250912)
	t.eq(a.archetype, b.archetype, "archetype is deterministic")
	var mismatches := 0
	for i in a.terrain.size():
		if a.terrain[i] != b.terrain[i]:
			mismatches += 1
		if absf(a.elevation[i] - b.elevation[i]) > 0.0001:
			mismatches += 1
	t.eq(mismatches, 0, "terrain and elevation are identical for one seed")

func test_different_seeds_produce_different_worlds(t: TestKit) -> void:
	var a := WorldData.new()
	var b := WorldData.new()
	WorldGen.generate(a, 1)
	WorldGen.generate(b, 2)
	var diff := 0
	for i in a.terrain.size():
		if a.terrain[i] != b.terrain[i]:
			diff += 1
	t.at_least(float(diff) / float(a.terrain.size()), 0.15, "worlds differ substantially")

func test_land_and_water_are_both_substantial(t: TestKit) -> void:
	for s in [11, 222, 3333, 44444]:
		var w := WorldData.new()
		WorldGen.generate(w, s)
		var total := float(w.land_cells + w.water_cells)
		t.eq(int(total), w.w * w.h, "every cell is land or water")
		var water_share := float(w.water_cells) / total
		t.between(water_share, 0.15, 0.80, "seed %d has a sane water share" % s)

func test_elevation_and_fields_are_normalised(t: TestKit) -> void:
	var w := WorldData.new()
	WorldGen.generate(w, 6161)
	for i in range(0, w.elevation.size(), 37):
		t.between(w.elevation[i], 0.0, 1.0, "elevation normalised")
		t.between(w.moisture[i], 0.0, 1.0, "moisture normalised")
		t.between(w.veg[i], 0.0, 1.0, "vegetation normalised")
		t.between(w.temperature[i], -80.0, 140.0, "temperature plausible")

func test_vegetation_only_on_fertile_ground(t: TestKit) -> void:
	var w := WorldData.new()
	WorldGen.generate(w, 8080)
	for i in range(0, w.veg.size(), 11):
		var cap: float = Terrain.FERTILITY[w.terrain[i]]
		t.at_most(w.veg[i], cap + 0.0001, "vegetation within material capacity")

func test_biome_variety(t: TestKit) -> void:
	var w := WorldData.new()
	WorldGen.generate(w, 1357)
	var seen := {}
	for i in w.biome.size():
		seen[w.biome[i]] = true
	t.at_least(float(seen.size()), 5.0, "a world contains several biomes")

func test_shoreline_band_exists(t: TestKit) -> void:
	var w := WorldData.new()
	WorldGen.generate(w, 2468)
	var shore_cells := 0
	for i in w.shore.size():
		if w.shore[i] > 0:
			shore_cells += 1
	t.at_least(float(shore_cells), 200.0, "a shoreline band was baked")

func test_rivers_or_lakes_exist_inland(t: TestKit) -> void:
	# Inland fresh water: water cells that are not connected to the map border
	# region by elevation (approximated by being well above the deep shelf).
	var found := 0
	for s in [777, 4242, 90210]:
		var w := WorldData.new()
		WorldGen.generate(w, s)
		for y in range(20, w.h - 20):
			for x in range(20, w.w - 20):
				var i := y * w.w + x
				if Terrain.is_water(w.terrain[i]) and w.moisture[i] > 0.5:
					found += 1
	t.at_least(float(found), 50.0, "inland water bodies are generated")

func test_terrain_changes_are_tracked(t: TestKit) -> void:
	var w := WorldData.new()
	WorldGen.generate(w, 31415)
	t.eq(w.modified.size(), 0, "a fresh world has no delta")
	var land := -1
	for i in w.terrain.size():
		if w.terrain[i] == Terrain.T.GRASS:
			land = i
			break
	t.check(land >= 0, "found a grass cell to edit")
	if land >= 0:
		w.set_terrain(land, Terrain.T.ROCK)
		t.eq(w.terrain[land], Terrain.T.ROCK, "terrain changed")
		t.at_least(float(w.modified.size()), 1.0, "change recorded in the delta")
		w.set_terrain(land, Terrain.T.ROCK)
		t.eq(w.modified.size(), 1, "recording is idempotent")
