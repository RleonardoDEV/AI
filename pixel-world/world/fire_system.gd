class_name FireSystem
extends RefCounted
## Cellular fire propagation over the active-cell list only, so a calm world
## costs nothing. Fire consumes vegetation as fuel, spreads with the wind,
## is suppressed by moisture/snow, heats the air around it and leaves ash.

const MAX_ACTIVE: int = 2600
const HEAT_RADIUS: int = 3

var ignitions: int = 0
var cells_burned: int = 0
## Positions where a fresh flame appeared this step (for spark particles).
var spark_events: PackedVector2Array = PackedVector2Array()
var smoke_events: PackedVector2Array = PackedVector2Array()

func update(ctx: SimContext, dt: float, wind: Vector2) -> void:
	var world := ctx.world
	var active := world.burning_cells
	spark_events.resize(0)
	smoke_events.resize(0)
	if active.is_empty():
		return

	var w := world.w
	var h := world.h
	var rng := ctx.rng
	var next := PackedInt32Array()
	var spread_chance := GameConfig.FIRE_SPREAD_BASE * dt
	var wind_len: float = wind.length()
	var wind_dir: Vector2 = wind.normalized() if wind_len > 0.01 else Vector2.ZERO

	for k in active.size():
		var i: int = active[k]
		var f: float = world.fire[i]
		if f <= 0.01:
			continue
		var x := i % w
		var y := int(i / w)

		# --- Burn fuel ----------------------------------------------------
		var fuel: float = world.veg[i]
		var burn: float = minf(fuel, GameConfig.FIRE_FUEL_BURN * dt * (0.4 + f))
		world.veg[i] = fuel - burn
		# Rain and snow fight the flame.
		var damp: float = world.water[i] * 2.4 + world.snow[i] * 1.8
		f += burn * 1.4 - dt * (0.10 + damp) - (0.18 * dt if fuel < 0.04 else 0.0)
		f = clampf(f, 0.0, 1.0)
		world.fire[i] = f
		world.mark_dirty(i)
		world.water[i] = maxf(0.0, world.water[i] - dt * 0.25)
		world.snow[i] = maxf(0.0, world.snow[i] - dt * 0.6)

		# --- Local heating ------------------------------------------------
		for dy in range(-HEAT_RADIUS, HEAT_RADIUS + 1):
			var yy := y + dy
			if yy < 0 or yy >= h:
				continue
			for dx in range(-HEAT_RADIUS, HEAT_RADIUS + 1):
				var xx := x + dx
				if xx < 0 or xx >= w:
					continue
				var j := yy * w + xx
				var fall := 1.0 - (absf(float(dx)) + absf(float(dy))) / float(HEAT_RADIUS * 2 + 1)
				world.temperature[j] = minf(world.temperature[j] + f * fall * 26.0 * dt,
						world.base_temp[j] + 90.0)

		if f <= 0.01:
			# Burned out: scorched earth.
			world.fire[i] = 0.0
			cells_burned += 1
			if world.veg[i] < 0.05 and rng.randf() < 0.55:
				world.set_terrain(i, Terrain.T.ASH)
			continue

		next.append(i)
		if rng.randf() < dt * 3.0:
			smoke_events.append(Vector2(float(x) + rng.randf(), float(y) + rng.randf()))

		# --- Spread -------------------------------------------------------
		if next.size() >= MAX_ACTIVE:
			continue
		for d in 4:
			var nx := x + FireSystem._DX[d]
			var ny := y + FireSystem._DY[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j2 := ny * w + nx
			if world.fire[j2] > 0.02:
				continue
			var flam: float = Terrain.FLAMMABILITY[world.terrain[j2]]
			if flam <= 0.01:
				continue
			var p := spread_chance * flam * (0.35 + world.veg[j2] * 1.5) * (0.5 + f)
			# Downwind spread is much faster.
			if wind_dir != Vector2.ZERO:
				var align := wind_dir.dot(Vector2(float(FireSystem._DX[d]), float(FireSystem._DY[d])))
				p *= 1.0 + maxf(0.0, align) * wind_len * 2.2
			p *= 1.0 - clampf(world.water[j2] * 3.0 + world.snow[j2] * 2.0, 0.0, 1.0)
			p *= 1.0 - world.moisture[j2] * 0.35
			if rng.randf() < p:
				if world.ignite(j2, 0.35 + f * 0.4):
					ignitions += 1
					spark_events.append(Vector2(float(nx) + 0.5, float(ny) + 0.5))
	world.burning_cells = next

const _DX: PackedInt32Array = [1, -1, 0, 0]
const _DY: PackedInt32Array = [0, 0, 1, -1]

func active_count(world: WorldData) -> int:
	return world.burning_cells.size()
