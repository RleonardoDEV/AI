class_name WorldGen
extends RefCounted
## Seeded procedural world generation.
##
## Pipeline: elevation (warped fractal noise + archetype falloff) -> rivers ->
## moisture (noise + distance to water) -> temperature (latitude + lapse rate)
## -> biome classification -> materials -> volcanism -> baked shade/shore ->
## vegetation. The same seed always yields the same world.

enum Archetype { CONTINENT, ARCHIPELAGO, LAKELAND, PANGAEA }
const ARCHETYPE_NAMES: PackedStringArray = ["Continent", "Archipelago", "Lakeland", "Pangaea"]

## Flora scattered by the generator: [{pos, variant, stage, kind}]
static var last_flora: Array[Dictionary] = []

static func generate(world: WorldData, world_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	world.world_seed = world_seed
	var w := world.w
	var h := world.h
	var n := w * h

	var arch: int = [Archetype.CONTINENT, Archetype.CONTINENT, Archetype.ARCHIPELAGO,
			Archetype.LAKELAND, Archetype.PANGAEA][rng.randi_range(0, 4)]
	world.archetype = arch

	# --- Noise sources ----------------------------------------------------
	var base := FastNoiseLite.new()
	base.seed = world_seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.0075 * (1.0 if arch != Archetype.ARCHIPELAGO else 1.85)
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = 4
	base.fractal_lacunarity = 2.1
	base.fractal_gain = 0.5
	base.domain_warp_enabled = true
	base.domain_warp_amplitude = 26.0
	base.domain_warp_frequency = 0.012

	var ridge := FastNoiseLite.new()
	ridge.seed = world_seed + 991
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.frequency = 0.016
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 3

	var detail := FastNoiseLite.new()
	detail.seed = world_seed + 5150
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = 0.055

	var moist_noise := FastNoiseLite.new()
	moist_noise.seed = world_seed + 20202
	moist_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moist_noise.frequency = 0.0115
	moist_noise.fractal_octaves = 3

	var temp_noise := FastNoiseLite.new()
	temp_noise.seed = world_seed + 31313
	temp_noise.frequency = 0.009

	var mask_warp := FastNoiseLite.new()
	mask_warp.seed = world_seed + 777
	mask_warp.frequency = 0.0062

	# Archetype-specific falloff and target water coverage.
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	var ecc := rng.randf_range(0.8, 1.25)
	var falloff_gain := 1.0
	var falloff_power := 2.3
	var water_share := 0.42
	match arch:
		Archetype.CONTINENT:
			falloff_gain = 1.05
			falloff_power = 2.2
			water_share = rng.randf_range(0.38, 0.46)
		Archetype.ARCHIPELAGO:
			falloff_gain = 0.6
			falloff_power = 1.6
			water_share = rng.randf_range(0.55, 0.66)
		Archetype.LAKELAND:
			falloff_gain = 0.5
			falloff_power = 3.0
			water_share = rng.randf_range(0.4, 0.5)
		Archetype.PANGAEA:
			falloff_gain = 0.34
			falloff_power = 4.0
			water_share = rng.randf_range(0.24, 0.33)

	# --- Raw relief -------------------------------------------------------
	var relief := PackedFloat32Array()
	relief.resize(n)
	var lo := INF
	var hi := -INF
	for y in h:
		var fy := float(y)
		for x in w:
			var i := y * w + x
			var fx := float(x)
			var e := base.get_noise_2d(fx, fy) * 0.5 + 0.5
			var r := ridge.get_noise_2d(fx, fy) * 0.5 + 0.5
			e = e * 0.72 + r * r * 0.38 * smoothstep(0.40, 0.78, e)
			var dx := (fx - cx) / (cx * ecc)
			var dy := (fy - cy) / (cy / ecc)
			var d := sqrt(dx * dx + dy * dy) + mask_warp.get_noise_2d(fx, fy) * 0.3
			e -= pow(clampf(d, 0.0, 1.7), falloff_power) * falloff_gain * 0.7
			relief[i] = e
			lo = minf(lo, e)
			hi = maxf(hi, e)
	var span := maxf(0.0001, hi - lo)
	for i in n:
		relief[i] = (relief[i] - lo) / span

	# Hillshade is baked from the *raw* relief: histogram remapping flattens
	# the field for classification, but relief is what the eye reads.
	_bake_shade(world, relief)

	# --- Histogram remap -> exact water coverage and land band shares -----
	_remap_elevation(world, relief, water_share)

	# --- Rivers (carved after remapping so channels reach water level) ----
	_carve_rivers(world, relief, rng, 6 + rng.randi_range(0, 6))

	# --- Water mask -> moisture -------------------------------------------
	var water_mask := PackedByteArray()
	water_mask.resize(n)
	for i in n:
		water_mask[i] = 1 if world.elevation[i] < GameConfig.SEA_LEVEL else 0
	var water_prox := _distance_field(world, water_mask, 24)

	# --- Climate, biomes, materials ---------------------------------------
	var lat_bias := rng.randf_range(-0.1, 0.1)
	var global_warm := rng.randf_range(-3.0, 4.0)
	for y in h:
		var fy := float(y)
		var lat: float = absf((fy / float(h)) * 2.0 - 1.0 + lat_bias)
		var lat_temp := 32.0 - pow(lat, 1.3) * 46.0 + global_warm
		for x in w:
			var i := y * w + x
			var fx := float(x)
			var e := world.elevation[i]
			var det := detail.get_noise_2d(fx, fy)
			# Contrast-boosted moisture so deserts and rainforests both exist.
			var mn := moist_noise.get_noise_2d(fx, fy) * 0.5 + 0.5
			mn = clampf((mn - 0.5) * 1.55 + 0.5, 0.0, 1.0)
			var m := clampf(mn * 0.72 + water_prox[i] * 0.42, 0.0, 1.0)
			world.moisture[i] = m

			var t := lat_temp + temp_noise.get_noise_2d(fx, fy) * 5.0
			t -= maxf(0.0, e - GameConfig.SEA_LEVEL) * 52.0
			world.base_temp[i] = t
			world.temperature[i] = t

			var b := Biome.classify(e, m, t)
			world.biome[i] = b
			world.terrain[i] = Biome.terrain_for(b, e, m, t, det)
			# Cheap integer hash for per-cell albedo jitter (no noise call).
			world.variation[i] = ((x * 73856093) ^ (y * 19349663) ^ (world_seed * 83492791)) & 255

	# --- Volcanism --------------------------------------------------------
	var volcano_count := 0
	if rng.randf() < 0.6:
		volcano_count = rng.randi_range(1, 2)
	for v in volcano_count:
		_raise_volcano(world, rng)

	# --- Derived layers ---------------------------------------------------
	_bake_shore(world)
	world.land_cells = 0
	world.water_cells = 0
	for i in n:
		if Terrain.is_water(world.terrain[i]):
			world.water_cells += 1
		else:
			world.land_cells += 1
		var fert: float = Terrain.FERTILITY[world.terrain[i]]
		world.veg[i] = clampf(fert * (0.35 + world.moisture[i] * 0.75), 0.0, fert)
		world.fire[i] = 0.0
		world.water[i] = 0.0
		world.snow[i] = 1.0 if world.terrain[i] == Terrain.T.SNOW else 0.0

	_scatter_flora(world, rng)
	world.full_redraw = true

# --------------------------------------------------------------------------
# Elevation remapping
# --------------------------------------------------------------------------
## Rank-based remap: a 512-bin CDF converts the noise field into a uniform
## rank, then an explicit piecewise curve assigns exact coverage to deep water,
## shallows, coast, lowland and mountain. Without this, the thresholds drift
## wildly between seeds and most worlds come out as one grey massif.
static func _remap_elevation(world: WorldData, relief: PackedFloat32Array, water_share: float) -> void:
	const BINS := 512
	var n := relief.size()
	var hist := PackedInt32Array()
	hist.resize(BINS)
	for i in n:
		var b := clampi(int(relief[i] * float(BINS - 1)), 0, BINS - 1)
		hist[b] += 1
	var cdf := PackedFloat32Array()
	cdf.resize(BINS)
	var acc := 0
	for b in BINS:
		acc += hist[b]
		cdf[b] = float(acc) / float(n)

	var sea := GameConfig.SEA_LEVEL
	var beach := GameConfig.BEACH_LEVEL
	var rock := GameConfig.ROCK_LEVEL
	var ws: float = clampf(water_share, 0.1, 0.85)
	for i in n:
		var b := clampi(int(relief[i] * float(BINS - 1)), 0, BINS - 1)
		var rank: float = cdf[b]
		var e := 0.0
		if rank < ws:
			# Water column: 45% abyss, 43% open water, 12% shallows.
			var wt := rank / ws
			if wt < 0.45:
				e = lerpf(0.02, sea - 0.10, wt / 0.45)
			elif wt < 0.88:
				e = lerpf(sea - 0.10, sea - 0.02, (wt - 0.45) / 0.43)
			else:
				e = lerpf(sea - 0.02, sea - 0.001, (wt - 0.88) / 0.12)
		else:
			# Land column: 4% coast, 84% habitable band, 12% highland.
			var lt := (rank - ws) / maxf(0.001, 1.0 - ws)
			if lt < 0.04:
				e = lerpf(sea, beach, lt / 0.04)
			elif lt < 0.88:
				e = lerpf(beach, rock, (lt - 0.04) / 0.84)
			else:
				e = lerpf(rock, 1.0, (lt - 0.88) / 0.12)
		world.elevation[i] = e

## Hillshade from the raw relief gradient (north-west light).
static func _bake_shade(world: WorldData, relief: PackedFloat32Array) -> void:
	var w := world.w
	var h := world.h
	for y in h:
		for x in w:
			var i := y * w + x
			var xl := relief[y * w + world.clamp_x(x - 1)]
			var xr := relief[y * w + world.clamp_x(x + 1)]
			var yu := relief[world.clamp_y(y - 1) * w + x]
			var yd := relief[world.clamp_y(y + 1) * w + x]
			var slope := (xl - xr) + (yu - yd)
			world.shade[i] = int(clampf(0.5 + slope * 9.0, 0.0, 1.0) * 255.0)

## O(n) shoreline band: mark the waterline, then dilate twice.
static func _bake_shore(world: WorldData) -> void:
	var w := world.w
	var h := world.h
	var n := w * h
	var sh := world.shore
	for i in n:
		sh[i] = 0
	for y in h:
		for x in w:
			var i := y * w + x
			var here := Terrain.is_water(world.terrain[i])
			var boundary := false
			if x > 0 and Terrain.is_water(world.terrain[i - 1]) != here:
				boundary = true
			elif x < w - 1 and Terrain.is_water(world.terrain[i + 1]) != here:
				boundary = true
			elif y > 0 and Terrain.is_water(world.terrain[i - w]) != here:
				boundary = true
			elif y < h - 1 and Terrain.is_water(world.terrain[i + w]) != here:
				boundary = true
			if boundary:
				sh[i] = 255
	# Two dilation passes give a 3-cell foam band.
	for pass_i in 2:
		var level := 160 - pass_i * 60
		var src := sh.duplicate()
		for y in h:
			for x in w:
				var i := y * w + x
				if src[i] != 0:
					continue
				var near := false
				if x > 0 and src[i - 1] > level:
					near = true
				elif x < w - 1 and src[i + 1] > level:
					near = true
				elif y > 0 and src[i - w] > level:
					near = true
				elif y < h - 1 and src[i + w] > level:
					near = true
				if near:
					sh[i] = level
	world.shore = sh

# --------------------------------------------------------------------------
# Rivers
# --------------------------------------------------------------------------
## Drops sources on high ground and walks them downhill, carving a channel.
static func _carve_rivers(world: WorldData, relief: PackedFloat32Array,
		rng: RandomNumberGenerator, count: int) -> void:
	var w := world.w
	var h := world.h
	for r in count:
		var sx := 0
		var sy := 0
		var found := false
		for attempt in 220:
			sx = rng.randi_range(8, w - 9)
			sy = rng.randi_range(8, h - 9)
			if world.elevation[sy * w + sx] > 0.66:
				found = true
				break
		if not found:
			continue
		var x := sx
		var y := sy
		var width := rng.randf_range(0.7, 1.6)
		var dir := Vector2.ZERO
		for step in 900:
			var i := y * w + x
			if world.elevation[i] < GameConfig.SEA_LEVEL:
				break
			# Carve a soft channel around the current point.
			var rad := int(ceil(width)) + 1
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var nx := x + dx
					var ny := y + dy
					if not world.in_bounds(nx, ny):
						continue
					var dist := sqrt(float(dx * dx + dy * dy))
					if dist > width + 1.0:
						continue
					var j := ny * w + nx
					if dist <= width:
						# Channel bed: pushed to shallow-water depth.
						world.elevation[j] = minf(world.elevation[j], GameConfig.SEA_LEVEL - 0.012)
					elif world.elevation[j] > GameConfig.SEA_LEVEL:
						# Bank: eroded but still dry, reads as a river valley.
						world.elevation[j] = maxf(GameConfig.SEA_LEVEL + 0.003,
								world.elevation[j] - 0.025)
			# Steepest descent on the smooth relief, biased by momentum so the
			# channel keeps its course across flats instead of stalling.
			var best_score := INF
			var bx := x
			var by := y
			for dy2 in range(-1, 2):
				for dx2 in range(-1, 2):
					if dx2 == 0 and dy2 == 0:
						continue
					var nx2 := x + dx2
					var ny2 := y + dy2
					if not world.in_bounds(nx2, ny2):
						continue
					var e := relief[ny2 * w + nx2] + rng.randf() * 0.0015
					# Reward continuing in the current direction.
					e -= (float(dx2) * dir.x + float(dy2) * dir.y) * 0.0022
					if e < best_score:
						best_score = e
						bx = nx2
						by = ny2
			if bx == x and by == y:
				_flood_pool(world, x, y, rng.randi_range(2, 4))
				break
			if relief[by * w + bx] > relief[y * w + x] + 0.006:
				# Uphill only: the river has filled a basin.
				_flood_pool(world, x, y, rng.randi_range(2, 4))
				break
			dir = Vector2(float(bx - x), float(by - y)).normalized()
			x = bx
			y = by
			width = minf(2.6, width + 0.004)

static func _flood_pool(world: WorldData, cx: int, cy: int, rad: int) -> void:
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var d := sqrt(float(dx * dx + dy * dy))
			if d > float(rad):
				continue
			var x := cx + dx
			var y := cy + dy
			if not world.in_bounds(x, y):
				continue
			var j := y * world.w + x
			world.elevation[j] = minf(world.elevation[j], GameConfig.SEA_LEVEL - 0.02)

# --------------------------------------------------------------------------
# Distance field (moisture from water proximity)
# --------------------------------------------------------------------------
## Two-pass chamfer distance transform, normalised and inverted so that 1.0
## means "on the waterline".
static func _distance_field(world: WorldData, mask: PackedByteArray, max_d: int) -> PackedFloat32Array:
	var w := world.w
	var h := world.h
	var n := w * h
	var dist := PackedFloat32Array()
	dist.resize(n)
	var big := float(max_d) * 2.0
	for i in n:
		dist[i] = 0.0 if mask[i] == 1 else big
	# Forward pass
	for y in h:
		for x in w:
			var i := y * w + x
			var d := dist[i]
			if x > 0:
				d = minf(d, dist[i - 1] + 1.0)
			if y > 0:
				d = minf(d, dist[i - w] + 1.0)
			if x > 0 and y > 0:
				d = minf(d, dist[i - w - 1] + 1.41)
			dist[i] = d
	# Backward pass
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			var d := dist[i]
			if x < w - 1:
				d = minf(d, dist[i + 1] + 1.0)
			if y < h - 1:
				d = minf(d, dist[i + w] + 1.0)
			if x < w - 1 and y < h - 1:
				d = minf(d, dist[i + w + 1] + 1.41)
			dist[i] = d
	for i in n:
		dist[i] = clampf(1.0 - dist[i] / float(max_d), 0.0, 1.0)
	return dist

# --------------------------------------------------------------------------
# Volcanism
# --------------------------------------------------------------------------
static func _raise_volcano(world: WorldData, rng: RandomNumberGenerator) -> void:
	var w := world.w
	var h := world.h
	var cx := 0
	var cy := 0
	for attempt in 260:
		cx = rng.randi_range(20, w - 21)
		cy = rng.randi_range(20, h - 21)
		if world.elevation[cy * w + cx] > GameConfig.BEACH_LEVEL + 0.04:
			break
	var rad := rng.randi_range(9, 15)
	for dy in range(-rad - 3, rad + 4):
		for dx in range(-rad - 3, rad + 4):
			var x := cx + dx
			var y := cy + dy
			if not world.in_bounds(x, y):
				continue
			var d := sqrt(float(dx * dx + dy * dy))
			if d > float(rad) + 3.0:
				continue
			var i := y * w + x
			var t := clampf(1.0 - d / float(rad), 0.0, 1.0)
			world.elevation[i] = clampf(world.elevation[i] + pow(t, 1.5) * 0.42, 0.0, 1.0)
			if d < float(rad) * 0.28:
				world.terrain[i] = Terrain.T.LAVA
				world.biome[i] = Biome.B.VOLCANIC
			elif d < float(rad) * 0.72:
				world.terrain[i] = Terrain.T.ASH
				world.biome[i] = Biome.B.VOLCANIC
			elif d < float(rad):
				world.terrain[i] = Terrain.T.ROCK
			world.base_temp[i] += (1.0 - d / float(rad + 3)) * 22.0
			world.temperature[i] = world.base_temp[i]

# --------------------------------------------------------------------------
# Flora scattering
# --------------------------------------------------------------------------
static func _scatter_flora(world: WorldData, rng: RandomNumberGenerator) -> void:
	last_flora = []
	var w := world.w
	var h := world.h
	var budget := GameConfig.MAX_TREES
	# Jittered grid sampling keeps a natural spread without a Poisson pass.
	var step := 2
	for gy in range(1, h - 1, step):
		for gx in range(1, w - 1, step):
			if last_flora.size() >= budget:
				return
			var x := gx + rng.randi_range(0, step - 1)
			var y := gy + rng.randi_range(0, step - 1)
			if not world.in_bounds(x, y):
				continue
			var i := y * w + x
			var b: int = world.biome[i]
			var t: int = world.terrain[i]
			if Terrain.is_water(t) or t == Terrain.T.LAVA:
				continue
			var tree_p: float = Biome.TREE_DENSITY[b] * (0.45 + world.moisture[i])
			var shrub_p: float = Biome.SHRUB_DENSITY[b] * (0.5 + world.moisture[i])
			var roll := rng.randf()
			if roll < tree_p:
				last_flora.append({
					"pos": Vector2(float(x) + rng.randf(), float(y) + rng.randf()),
					"variant": rng.randi_range(0, PixelArt.TREE_VARIANTS - 1),
					"stage": rng.randi_range(1, PixelArt.TREE_STAGES - 1),
					"kind": 0,
				})
			elif roll < tree_p + shrub_p:
				last_flora.append({
					"pos": Vector2(float(x) + rng.randf(), float(y) + rng.randf()),
					"variant": rng.randi_range(0, 7),
					"stage": 0,
					"kind": 1,
				})
