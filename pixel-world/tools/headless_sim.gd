extends Node
## Headless fast-simulation harness. Runs the full simulation with no
## rendering so thousands of ticks can be validated in seconds.
##
##   godot --headless --script tools/headless_sim.gd -- seed=777 frames=4000 speed=100
##
## Prints a periodic census plus a final report. Used both as a smoke test and
## to balance the ecology.

func _ready() -> void:
	var opts := {"seed": 777, "frames": 3000, "speed": 6, "report": 500, "quiet": 0}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			opts[kv[0].lstrip("-")] = int(kv[1])

	var sim := Simulation.new()
	var t0 := Time.get_ticks_msec()
	sim.build(int(opts["seed"]))
	var build_ms := Time.get_ticks_msec() - t0
	sim.set_speed_index(int(opts["speed"]))

	print("PIXEL WORLD headless simulation")
	print("  seed        : %d (%s)" % [sim.world_seed, WorldGen.ARCHETYPE_NAMES[sim.world.archetype]])
	print("  build       : %d ms" % build_ms)
	print("  speed       : %s" % sim.speed_label())
	print("  start pop   : %d across %d species" % [sim.population(), sim.species_count()])
	print("  land/water  : %d / %d cells" % [sim.world.land_cells, sim.world.water_cells])
	print("  flora       : %d" % sim.flora.count)
	print("founding census:")
	for sp in sim.registry.species:
		print("  %-22s pop %4d  %-10s  diet %.2f size %.2f speed %.2f fert %.2f life %.0f" % [
			sp.full_name(), sp.population, sp.diet_label(), sp.centroid[DNA.G.DIET],
			sp.centroid[DNA.G.SIZE], sp.centroid[DNA.G.SPEED],
			sp.centroid[DNA.G.FERTILITY], sp.centroid[DNA.G.LIFESPAN]])
	print("")
	print("%8s %7s %6s %5s %7s %7s %6s %6s %6s %7s %6s %6s" % [
		"frame", "tick", "pop", "spec", "births", "deaths", "gen", "maxgen",
		"temp", "veg", "fires", "carn"])

	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	var frames := int(opts["frames"])
	var report := int(opts["report"])
	var dt := 1.0 / 60.0
	var t_sim := Time.get_ticks_usec()
	var worst_frame := 0.0
	var total_ticks := 0
	var extinct_at := -1

	for f in range(1, frames + 1):
		var f0 := Time.get_ticks_usec()
		total_ticks += sim.advance(dt, view)
		var fms := float(Time.get_ticks_usec() - f0) / 1000.0
		worst_frame = maxf(worst_frame, fms)
		if sim.population() == 0 and extinct_at < 0:
			extinct_at = f
			print("!! total extinction at frame %d (tick %d, year %d)" % [f, sim.tick, sim.climate.year])
			break
		if f % report == 0:
			sim.rollup()
			_carnivore_report(sim)
			print("%8d %7d %6d %5d %7d %7d %6.1f %6d %6.1f %7.3f %6d %6d" % [
				f, sim.tick, sim.population(), sim.species_count(),
				sim.stats.births, sim.stats.deaths, sim.stats.avg_generation,
				sim.stats.max_generation, sim.stats.avg_temperature,
				sim.stats.total_vegetation, sim.world.burning_cells.size(),
				sim.stats.carnivores])
	var sim_ms := float(Time.get_ticks_usec() - t_sim) / 1000.0

	sim.rollup()
	print("")
	print("--- report ---------------------------------------------------")
	print("frames %d | sim ticks %d | wall %.0f ms | avg frame %.2f ms | worst %.2f ms" % [
		frames, total_ticks, sim_ms, sim_ms / float(frames), worst_frame])
	print("simulated time: %.1f days (%d years)" % [
		sim.climate.day + sim.climate.day_phase, sim.climate.year])
	print("population %d (peak %d) | species alive %d / created %d | extinctions %d" % [
		sim.population(), sim.stats.peak_population, sim.species_count(),
		sim.registry.total_species_created, sim.registry.total_extinctions])
	print("births %d | deaths %d | attacks %d | mutations %d" % [
		sim.stats.births, sim.stats.deaths, sim.stats.attacks, sim.stats.mutations])
	print("generations: avg %.2f max %d" % [sim.stats.avg_generation, sim.stats.max_generation])
	print("trophic: %d herbivores, %d omnivores, %d carnivores" % [
		sim.stats.herbivores, sim.stats.omnivores, sim.stats.carnivores])
	var causes := ["starvation", "dehydration", "old age", "predation", "fire",
			"drowning", "cold", "heat", "divine"]
	var cs := ""
	for i in causes.size():
		cs += "%s=%d " % [causes[i], sim.stats.deaths_by_cause[i]]
	print("deaths by cause: " + cs)
	print("weather: %s | events fired %d" % [sim.weather.label(), sim.weather.events_fired])
	var ev := ""
	for e in sim.weather.event_history:
		ev += "%s(y%d) " % [e["name"], e["year"]]
	print("event log: " + (ev if ev != "" else "(none)"))
	print("phase ms/frame: creatures %.2f | grid %.2f | world %.2f | growth %.2f | flora %.2f | weather %.2f" % [
		sim.profiler.avg("creatures"), sim.profiler.avg("grid"), sim.profiler.avg("world"),
		sim.profiler.avg("growth"), sim.profiler.avg("flora"), sim.profiler.avg("weather")])
	print("flora %d | corpses %d | stride %d | ticks/frame %d" % [
		sim.flora.count, sim.entities.corpse_count, sim.stride, sim.last_ticks()])
	print("")
	print("top species:")
	var living := sim.registry.living()
	living.sort_custom(func(a, b): return a.population > b.population)
	for k in mini(8, living.size()):
		var sp: Species = living[k]
		print("  %-22s pop %4d  gen %3d  %-10s  size %.2f speed %.2f aggr %.2f  parent %d" % [
			sp.full_name(), sp.population, sp.founder_generation, sp.diet_label(),
			sp.centroid[DNA.G.SIZE], sp.centroid[DNA.G.SPEED],
			sp.centroid[DNA.G.AGGRESSION], sp.parent_id])
	get_tree().quit()

## Diagnostic: why do the meat eaters die? Prints their vitals as a group.
func _carnivore_report(sim: Simulation) -> void:
	var n := 0
	var hunger := 0.0
	var energy := 0.0
	var age := 0.0
	var life := 0.0
	var adults := 0
	var drive := 0.0
	for k in sim.entities.alive_ids.size():
		var c: Creature = sim.entities.creatures[sim.entities.alive_ids[k]]
		if not c.alive or c.diet <= 0.62:
			continue
		n += 1
		hunger += c.hunger
		energy += c.energy
		age += c.age
		life += c.lifespan
		drive += c.repro_drive
		if c.is_adult():
			adults += 1
	if n == 0:
		print("        carnivores: none alive")
		return
	var d := float(n)
	print("        carnivores: %d (adults %d) hunger %.2f energy %.2f age %.1f/%.0f drive %.2f" % [
		n, adults, hunger / d, energy / d, age / d, life / d, drive / d])
