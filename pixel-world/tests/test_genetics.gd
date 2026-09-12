extends RefCounted
## Genome operators: bounds, inheritance, mutation, distance, speciation.

func _rng(seed_value: int = 99) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func test_random_genome_respects_bounds(t: TestKit) -> void:
	var rng := _rng()
	for trial in 40:
		var g := DNA.random_genome(rng)
		t.eq(g.size(), DNA.NUM_GENES, "genome length")
		for i in DNA.NUM_GENES:
			t.between(g[i], DNA.MIN[i], DNA.MAX[i], "gene %s in range" % DNA.NAMES[i])

func test_profile_genome_is_reproducible(t: TestKit) -> void:
	var profiles := SpeciesRegistry.starting_profiles()
	var a := DNA.from_profile(profiles[0]["genes"], _rng(7), 0.0)
	var b := DNA.from_profile(profiles[0]["genes"], _rng(7), 0.0)
	for i in DNA.NUM_GENES:
		t.approx(a[i], b[i], 0.0001, "same seed gives same genome")

func test_crossover_stays_between_parents(t: TestKit) -> void:
	var rng := _rng(11)
	var a := DNA.random_genome(rng)
	var b := DNA.random_genome(rng)
	for trial in 25:
		var c := DNA.crossover(a, b, rng)
		for i in DNA.NUM_GENES:
			var lo: float = minf(a[i], b[i])
			var hi: float = maxf(a[i], b[i])
			t.between(c[i], lo - 0.0001, hi + 0.0001,
					"child gene %s between parents" % DNA.NAMES[i])

func test_mutation_respects_bounds_and_moves_genes(t: TestKit) -> void:
	var rng := _rng(13)
	var g := DNA.random_genome(rng)
	var before := g.duplicate()
	var moved := 0
	for trial in 30:
		DNA.mutate(g, rng, 0.5, 0.05)
	for i in DNA.NUM_GENES:
		t.between(g[i], DNA.MIN[i], DNA.MAX[i], "mutated gene %s in range" % DNA.NAMES[i])
		if absf(g[i] - before[i]) > 0.0001:
			moved += 1
	t.at_least(float(moved), 8.0, "repeated mutation changes most genes")

func test_mutation_rate_zero_is_stable(t: TestKit) -> void:
	var rng := _rng(17)
	var g := DNA.random_genome(rng)
	var before := g.duplicate()
	DNA.mutate(g, rng, 0.0, 0.0)
	for i in DNA.NUM_GENES:
		t.approx(g[i], before[i], 0.0001, "no mutation at rate 0")

func test_distance_is_zero_for_identical_and_grows(t: TestKit) -> void:
	var rng := _rng(19)
	var a := DNA.random_genome(rng)
	t.approx(DNA.distance(a, a), 0.0, 0.0001, "distance to self is zero")
	var b := a.duplicate()
	b[DNA.G.DIET] = DNA.MAX[DNA.G.DIET]
	b[DNA.G.SIZE] = DNA.MAX[DNA.G.SIZE]
	var d1 := DNA.distance(a, b)
	b[DNA.G.SPEED] = DNA.MAX[DNA.G.SPEED]
	var d2 := DNA.distance(a, b)
	t.at_least(d1, 0.01, "differing genomes have distance")
	t.at_least(d2, d1, "more difference means more distance")
	t.at_most(d2, 1.01, "distance is normalised")

func test_colour_encodes_trophic_role(t: TestKit) -> void:
	var rng := _rng(23)
	var herb := DNA.random_genome(rng)
	herb[DNA.G.DIET] = 0.0
	var carn := herb.duplicate()
	carn[DNA.G.DIET] = 1.0
	var hc := DNA.color_of(herb)
	var cc := DNA.color_of(carn)
	t.check(absf(hc.h - cc.h) > 0.1, "herbivores and carnivores use distinct hues")
	# Neither band may sit on grass green (~0.33) or water cyan (~0.52).
	for c in [hc, cc]:
		t.check(absf(c.h - 0.33) > 0.10, "hue avoids grass green (got %.2f)" % c.h)
		t.check(absf(c.h - 0.52) > 0.08, "hue avoids water cyan (got %.2f)" % c.h)
	t.at_least(hc.v, 0.5, "creatures are bright enough to read")

func test_diet_labels(t: TestKit) -> void:
	t.eq(DNA.diet_label(0.0), "Herbivore", "low diet is herbivore")
	t.eq(DNA.diet_label(0.5), "Omnivore", "mid diet is omnivore")
	t.eq(DNA.diet_label(1.0), "Carnivore", "high diet is carnivore")

func test_speciation_triggers_on_drift(t: TestKit) -> void:
	var rng := _rng(29)
	var reg := SpeciesRegistry.new(1234)
	var founders := reg.seed_initial(rng)
	t.at_least(float(founders.size()), 6.0, "several founding species")
	var parent: Species = founders[0]
	parent.population = 10
	# A genome identical to the centroid must stay in the same species.
	var same := reg.classify(parent.id, parent.centroid.duplicate(), 0, 0, 2, rng)
	t.eq(same.id, parent.id, "identical genome stays in species")
	# A genome pushed to the far end of every gene must found a new one.
	var far := parent.centroid.duplicate()
	for i in DNA.NUM_GENES:
		far[i] = DNA.MAX[i] if parent.centroid[i] < (DNA.MIN[i] + DNA.MAX[i]) * 0.5 else DNA.MIN[i]
	var novel := reg.classify(parent.id, far, 10, 1, 3, rng)
	t.check(novel.id != parent.id, "large drift founds a new species")
	t.eq(novel.parent_id, parent.id, "new species records its ancestor")
	t.check(parent.children.has(novel.id), "ancestor records its descendant")
	t.at_most(float(novel.sprite_slot), float(GameConfig.MAX_SPECIES_SLOTS - 1), "sprite slot in range")

func test_single_mutant_cannot_fragment_a_tiny_species(t: TestKit) -> void:
	var rng := _rng(31)
	var reg := SpeciesRegistry.new(77)
	var founders := reg.seed_initial(rng)
	var parent: Species = founders[1]
	parent.population = 1  # below MIN_PARENT_POP
	var far := parent.centroid.duplicate()
	for i in DNA.NUM_GENES:
		far[i] = DNA.MAX[i] if parent.centroid[i] < (DNA.MIN[i] + DNA.MAX[i]) * 0.5 else DNA.MIN[i]
	var result := reg.classify(parent.id, far, 0, 0, 2, rng)
	t.eq(result.id, parent.id, "species too small to split")

func test_extinction_bookkeeping(t: TestKit) -> void:
	var rng := _rng(37)
	var reg := SpeciesRegistry.new(5)
	var founders := reg.seed_initial(rng)
	var sp: Species = founders[2]
	reg.on_birth(sp)
	reg.on_birth(sp)
	t.eq(sp.population, 2, "births counted")
	t.eq(sp.peak_population, 2, "peak tracked")
	reg.on_death(sp, 4)
	reg.on_death(sp, 5)
	t.eq(sp.population, 0, "deaths counted")
	t.check(sp.extinct, "species marked extinct at zero population")
	t.eq(sp.extinct_year, 5, "extinction year recorded")
	reg.on_birth(sp)
	t.check(not sp.extinct, "re-seeded species is no longer extinct")
