class_name WaterSystem
extends RefCounted
## Transient surface water: rain puddles that flow downhill, soak into the
## ground, evaporate faster when it is hot, and douse fire on the way.

var evaporation_mul: float = 1.0

## Upper bound on puddles processed per call. After heavy rain or a thaw the
## wet list can cover a large part of the map; processing all of it in one
## frame was the single worst frame-time spike in the simulation. Unprocessed
## puddles simply wait their turn — they keep their water in the meantime.
const MAX_PER_STEP: int = 2500

var _cursor: int = 0

func update(ctx: SimContext, dt: float) -> void:
	var world := ctx.world
	var wet := world.wet_cells
	var total := wet.size()
	if total == 0:
		return
	var w := world.w
	var h := world.h
	var next := PackedInt32Array()
	var budget: int = mini(total, MAX_PER_STEP)
	if _cursor >= total:
		_cursor = 0
	# Carry forward everything outside this frame's window untouched.
	if budget < total:
		for k in total:
			if k < _cursor or k >= _cursor + budget:
				next.append(wet[k])
	var start := _cursor
	var stop: int = mini(total, start + budget)
	_cursor = stop
	for k in range(start, stop):
		var i: int = wet[k]
		var amount: float = world.water[i]
		if amount <= 0.02:
			world.water[i] = 0.0
			world.mark_dirty(i)
			continue
		# Douse any flame here.
		if world.fire[i] > 0.0:
			world.fire[i] = maxf(0.0, world.fire[i] - dt * 1.6 * amount)
			amount -= dt * 0.2

		# Flow to the lowest lower neighbour.
		var x := i % w
		var y := int(i / w)
		var my_e: float = world.elevation[i]
		var best := -1
		var best_e := my_e
		for d in 4:
			var nx := x + _DX[d]
			var ny := y + _DY[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			var e: float = world.elevation[j]
			if e < best_e - 0.0015:
				best_e = e
				best = j
		if best >= 0 and amount > 0.06:
			var moved: float = minf(amount * 0.55, dt * 1.1 * amount)
			amount -= moved
			if Terrain.is_water(world.terrain[best]):
				pass  # merges into the sea / lake
			else:
				var before: float = world.water[best]
				world.water[best] = clampf(before + moved, 0.0, 1.0)
				if before <= 0.02:
					next.append(best)
				world.mark_dirty(best)

		# Soak + evaporate (hot ground dries quickly).
		var temp_mul: float = 1.0 + clampf((world.temperature[i] - 18.0) / 26.0, -0.4, 1.6)
		amount -= dt * GameConfig.WATER_EVAPORATION * 12.0 * temp_mul * evaporation_mul
		# Soaked ground becomes more fertile.
		world.moisture[i] = minf(1.0, world.moisture[i] + dt * 0.012)
		world.water[i] = maxf(0.0, amount)
		world.mark_dirty(i)
		if world.water[i] > 0.02:
			next.append(i)
	world.wet_cells = next

const _DX: PackedInt32Array = [1, -1, 0, 0]
const _DY: PackedInt32Array = [0, 0, 1, -1]
