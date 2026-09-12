extends Node
## Micro-benchmark for the simulation hot path.
##   godot --headless res://tools/bench.tscn -- seed=777 iters=40000

func _ready() -> void:
	var opts := {"seed": 777, "iters": 40000}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			opts[kv[0].lstrip("-")] = int(kv[1])
	var sim := Simulation.new()
	sim.build(int(opts["seed"]))
	sim.set_speed_index(3)
	# Warm the world up so the population and state are representative.
	var view := Rect2(0, 0, sim.world.w, sim.world.h)
	for f in 260:
		sim.advance(1.0 / 60.0, view)
	sim.entities.rebuild_grid()
	var ids := sim.entities.alive_ids
	if ids.is_empty():
		print("no population to benchmark")
		get_tree().quit()
		return
	var iters := int(opts["iters"])
	print("population %d | iterations %d" % [ids.size(), iters])

	var ctx := sim.ctx
	ctx.dt = 0.05
	var n := ids.size()

	print("%-28s %10s" % ["section", "us/call"])
	_bench("Perception.scan", iters, func(i: int) -> void:
		Perception.scan(ctx, sim.entities.creatures[ids[i % n]]))
	_bench("Perception.find_forage", iters, func(i: int) -> void:
		Perception.find_forage(ctx, sim.entities.creatures[ids[i % n]]))
	_bench("Perception.find_water", iters, func(i: int) -> void:
		Perception.find_water(ctx, sim.entities.creatures[ids[i % n]]))
	_bench("grid.query(cap40)", iters, func(i: int) -> void:
		var c: Creature = sim.entities.creatures[ids[i % n]]
		sim.entities.grid.query(c.pos.x, c.pos.y, 11.0, 40, c.id))
	_bench("Brain.think_and_act", iters, func(i: int) -> void:
		Brain.think_and_act(ctx, sim.entities.creatures[ids[i % n]], 0.05))
	_bench("EntityManager.update(tick)", int(iters / 40), func(i: int) -> void:
		sim.entities.update(ctx))
	get_tree().quit()

func _bench(label: String, iters: int, fn: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	for i in iters:
		fn.call(i)
	var dt := float(Time.get_ticks_usec() - t0)
	print("%-28s %10.2f" % [label, dt / float(iters)])
