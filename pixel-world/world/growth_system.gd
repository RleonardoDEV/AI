class_name GrowthSystem
extends RefCounted
## Vegetation regrowth, snow melt and thermal relaxation.
##
## These are whole-grid processes, so they run as a *chunked sweep*: a fixed
## slice of cells per call with a proportionally larger dt. Cost per frame is
## therefore constant no matter how fast the simulation is running — the
## single most important optimisation for the 100x speed setting.

const SLICES: int = 24
## Vegetation only changes the albedo in steps this large, so smaller
## changes are not worth re-baking.
const VEG_QUANTUM: float = 1.0 / 24.0

var cursor: int = 0
var growth_mul: float = 1.0

func update(ctx: SimContext, dt: float) -> void:
	var world := ctx.world
	var n := world.w * world.h
	var slice := int(n / SLICES)
	var start := cursor
	var end: int = mini(n, start + slice)
	# Each cell is visited once every SLICES calls, so it must advance by the
	# time accumulated across those calls.
	# Each cell is visited once per SLICES calls, so it advances by dt * SLICES.
	var eff_dt := dt * float(SLICES)
	var global_temp: float = ctx.climate.global_temp
	var regrow: float = GameConfig.VEG_REGROW * growth_mul

	for i in range(start, end):
		# --- Temperature relaxes toward climate baseline ------------------
		var base: float = world.base_temp[i] + global_temp
		var t: float = world.temperature[i]
		world.temperature[i] = t + (base - t) * clampf(eff_dt * 0.25, 0.0, 1.0)

		# --- Snow ---------------------------------------------------------
		var sn: float = world.snow[i]
		if sn > 0.0:
			if world.temperature[i] > 1.0:
				var melted: float = minf(sn, eff_dt * 0.035 * (world.temperature[i] - 1.0))
				world.snow[i] = sn - melted
				if melted > 0.001:
					world.add_water(i, melted * 0.4)
					world.mark_dirty(i)

		# --- Vegetation ---------------------------------------------------
		var fert: float = Terrain.FERTILITY[world.terrain[i]]
		if fert <= 0.01:
			continue
		var v: float = world.veg[i]
		if v >= fert - 0.002:
			continue
		if world.fire[i] > 0.02:
			continue
		# Growth needs warmth and water.
		var temp_ok: float = 1.0 - clampf(absf(world.temperature[i] - 21.0) / 30.0, 0.0, 1.0)
		var moist: float = clampf(world.moisture[i] * 0.8 + world.water[i] * 0.6, 0.0, 1.0)
		var rate: float = regrow * temp_ok * (0.18 + moist) * eff_dt
		if rate <= 0.0:
			continue
		# Logistic growth: sparse patches recover slowly, dense ones saturate.
		var head: float = fert - v
		var nv: float = minf(fert, v + rate * (0.25 + v / maxf(0.05, fert)) * head * 2.0)
		world.veg[i] = nv
		if int(nv / VEG_QUANTUM) != int(v / VEG_QUANTUM):
			world.mark_dirty(i)

	cursor = end
	if cursor >= n:
		cursor = 0
