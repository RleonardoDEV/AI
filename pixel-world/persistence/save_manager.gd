class_name SaveManager
extends RefCounted
## World persistence.
##
## A save is a *seed plus a delta*, not a dump of the grid. Loading regenerates
## the world from its seed (deterministic) and then replays the cells the
## player or the simulation permanently changed — craters, floods, raised rock,
## lava. Continuous fields that recover on their own (vegetation, snow,
## puddles) are stored quantised to one byte per cell, which compresses to
## almost nothing; temperature and hillshade are simply recomputed.
##
## The result is a file of tens of kilobytes for a 65k-cell world with 500
## animals, and a load that cannot drift from what generation would produce.

const PATH := "user://world.pxw"
const VERSION: int = 1

static func has_save() -> bool:
	return FileAccess.file_exists(PATH)

static func save_world(sim: Simulation) -> bool:
	var world := sim.world
	var data := {
		"version": VERSION,
		"seed": sim.world_seed,
		"tick": sim.tick,
		"elapsed": sim.elapsed_sim_time,
		"speed_index": sim.speed_index,
		"climate": sim.climate.serialize(),
		"weather": sim.weather.serialize(),
		"stats": sim.stats.serialize(),
		"registry": sim.registry.serialize(),
		"flora": sim.flora.serialize(),
		"delta": _pack_delta(world),
		"veg": _quantise(world.veg),
		"snow": _quantise(world.snow),
		"water": _quantise(world.water),
		"creatures": _pack_creatures(sim),
	}
	var f := FileAccess.open_compressed(PATH, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	if f == null:
		EventBus.toast.emit("Could not write save file", Color(1.0, 0.45, 0.4))
		return false
	f.store_var(data, true)
	f.close()
	var size := 0
	var check := FileAccess.open(PATH, FileAccess.READ)
	if check != null:
		size = check.get_length()
		check.close()
	EventBus.world_save_completed.emit(PATH)
	EventBus.toast.emit("World saved (%d KB, %d cells changed)" % [
			int(size / 1024), world.modified.size()], Color(0.55, 0.95, 0.7))
	return true

## Rebuilds a Simulation from disk, or null on failure.
static func load_world() -> Simulation:
	if not has_save():
		return null
	var f := FileAccess.open_compressed(PATH, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return null
	var data = f.get_var(true)
	f.close()
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != VERSION:
		EventBus.toast.emit("Save file is from another version", Color(1.0, 0.6, 0.35))
		return null

	var sim := Simulation.new()
	# Regenerating from the seed gives the exact baseline the delta applies to.
	sim.build(int(data["seed"]))
	# The generated founding population is replaced by the saved one.
	sim.entities.alive_ids.resize(0)
	sim.entities.free_ids.resize(0)
	for i in GameConfig.MAX_CREATURES:
		sim.entities.creatures[i].alive = false
		sim.entities.free_ids.append(GameConfig.MAX_CREATURES - 1 - i)
	sim.entities.population = 0

	var world := sim.world
	_apply_delta(world, data.get("delta", {}))
	_dequantise(data.get("veg", PackedByteArray()), world.veg)
	_dequantise(data.get("snow", PackedByteArray()), world.snow)
	_dequantise(data.get("water", PackedByteArray()), world.water)
	# Rebuild derived layers the save deliberately omits.
	world.wet_cells.resize(0)
	world.burning_cells.resize(0)
	for i in world.w * world.h:
		world.fire[i] = 0.0
		if world.water[i] > 0.02:
			world.wet_cells.append(i)
	world.recompute_shore()
	world.full_redraw = true

	sim.registry.deserialize(data.get("registry", {}))
	sim.climate.deserialize(data.get("climate", {}))
	sim.weather.deserialize(data.get("weather", {}))
	sim.stats.deserialize(data.get("stats", {}))
	sim.flora.deserialize(data.get("flora", {}), sim.rng)
	sim.tick = int(data.get("tick", 0))
	sim.ctx.tick = sim.tick
	sim.elapsed_sim_time = float(data.get("elapsed", 0.0))
	_unpack_creatures(sim, data.get("creatures", {}))
	sim.entities.rebuild_grid()
	sim.set_speed_index(int(data.get("speed_index", 2)))
	sim.rollup()
	EventBus.world_loaded.emit(sim.world_seed)
	EventBus.toast.emit("World %d restored — %d creatures, %d species" % [
			sim.world_seed, sim.population(), sim.species_count()], Color(0.6, 0.9, 1.0))
	return sim

# --------------------------------------------------------------------------
# Terrain delta
# --------------------------------------------------------------------------
static func _pack_delta(world: WorldData) -> Dictionary:
	var idx := PackedInt32Array()
	var terr := PackedByteArray()
	var elev := PackedFloat32Array()
	for k in world.modified.size():
		var i: int = world.modified[k]
		idx.append(i)
		terr.append(world.terrain[i])
		elev.append(world.elevation[i])
	return {"idx": idx, "terrain": terr, "elevation": elev}

static func _apply_delta(world: WorldData, d: Dictionary) -> void:
	var idx := PackedInt32Array(d.get("idx", PackedInt32Array()))
	var terr := PackedByteArray(d.get("terrain", PackedByteArray()))
	var elev := PackedFloat32Array(d.get("elevation", PackedFloat32Array()))
	world.clear_modified()
	for k in idx.size():
		var i: int = idx[k]
		if i < 0 or i >= world.terrain.size():
			continue
		if k < elev.size():
			world.elevation[i] = elev[k]
		if k < terr.size():
			world.terrain[i] = terr[k]
		world.mark_modified(i)
	# Land/water tallies must match the restored terrain.
	world.land_cells = 0
	world.water_cells = 0
	for i in world.terrain.size():
		if Terrain.is_water(world.terrain[i]):
			world.water_cells += 1
		else:
			world.land_cells += 1

# --------------------------------------------------------------------------
# Continuous fields, quantised to a byte each
# --------------------------------------------------------------------------
static func _quantise(src: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(src.size())
	for i in src.size():
		out[i] = clampi(int(src[i] * 255.0), 0, 255)
	return out

static func _dequantise(src: PackedByteArray, dst: PackedFloat32Array) -> void:
	var n: int = mini(src.size(), dst.size())
	for i in n:
		dst[i] = float(src[i]) / 255.0

# --------------------------------------------------------------------------
# Creatures, as parallel arrays
# --------------------------------------------------------------------------
static func _pack_creatures(sim: Simulation) -> Dictionary:
	var ids := sim.entities.alive_ids
	var n := 0
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var dna := PackedFloat32Array()
	var species := PackedInt32Array()
	var gen := PackedInt32Array()
	var vitals := PackedFloat32Array()
	var state := PackedByteArray()
	var mem := PackedVector2Array()
	for k in ids.size():
		var c: Creature = sim.entities.creatures[ids[k]]
		if not c.alive:
			continue
		n += 1
		pos.append(c.pos)
		vel.append(c.vel)
		dna.append_array(c.dna)
		species.append(c.species_id)
		gen.append(c.generation)
		vitals.append_array([c.age, c.health, c.energy, c.hunger, c.thirst,
				c.repro_drive, c.fear, c.breed_cooldown])
		state.append(c.state)
		mem.append(c.mem_water)
		mem.append(c.mem_food)
		mem.append(c.mem_home)
	return {"n": n, "pos": pos, "vel": vel, "dna": dna, "species": species,
			"gen": gen, "vitals": vitals, "state": state, "mem": mem}

static func _unpack_creatures(sim: Simulation, d: Dictionary) -> void:
	var n := int(d.get("n", 0))
	if n <= 0:
		return
	var pos := PackedVector2Array(d.get("pos", PackedVector2Array()))
	var vel := PackedVector2Array(d.get("vel", PackedVector2Array()))
	var dna := PackedFloat32Array(d.get("dna", PackedFloat32Array()))
	var species := PackedInt32Array(d.get("species", PackedInt32Array()))
	var gen := PackedInt32Array(d.get("gen", PackedInt32Array()))
	var vitals := PackedFloat32Array(d.get("vitals", PackedFloat32Array()))
	var state := PackedByteArray(d.get("state", PackedByteArray()))
	var mem := PackedVector2Array(d.get("mem", PackedVector2Array()))
	var genes := DNA.NUM_GENES
	for k in n:
		if k >= pos.size() or (k + 1) * genes > dna.size():
			break
		var sp := sim.registry.get_species(species[k] if k < species.size() else 0)
		if sp == null:
			continue
		var genome := dna.slice(k * genes, (k + 1) * genes)
		var c := sim.entities.spawn(sim.ctx, sp, genome, pos[k],
				gen[k] if k < gen.size() else 1)
		if c == null:
			break
		if k < vel.size():
			c.vel = vel[k]
		var base := k * 8
		if base + 7 < vitals.size():
			c.age = vitals[base]
			c.health = vitals[base + 1]
			c.energy = vitals[base + 2]
			c.hunger = vitals[base + 3]
			c.thirst = vitals[base + 4]
			c.repro_drive = vitals[base + 5]
			c.fear = vitals[base + 6]
			c.breed_cooldown = vitals[base + 7]
		if k < state.size():
			c.state = state[k]
		var mb := k * 3
		if mb + 2 < mem.size():
			c.mem_water = mem[mb]
			c.mem_food = mem[mb + 1]
			c.mem_home = mem[mb + 2]
