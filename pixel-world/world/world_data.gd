class_name WorldData
extends RefCounted
## The world is a set of parallel flat arrays (structure-of-arrays), not a tree
## of nodes. 65k cells stay cache-friendly, serialise in one block, and let the
## renderer bake straight into an image without touching the scene tree.

var w: int
var h: int
var world_seed: int = 0
var archetype: int = 0

# --- Per-cell state -------------------------------------------------------
var terrain: PackedByteArray          # Terrain.T
var biome: PackedByteArray            # Biome.B
var elevation: PackedFloat32Array     # [0,1]
var moisture: PackedFloat32Array      # [0,1]
var temperature: PackedFloat32Array   # degrees C, live field
var base_temp: PackedFloat32Array     # climate baseline (no events)
var veg: PackedFloat32Array           # [0,1] edible biomass
var fire: PackedFloat32Array          # [0,1] burn intensity
var water: PackedFloat32Array         # [0,1] transient surface water on land
var snow: PackedFloat32Array          # [0,1] snow cover
var shade: PackedByteArray            # baked hillshade, 128 = neutral
var variation: PackedByteArray        # per-cell albedo jitter
var shore: PackedByteArray            # 255 at the waterline, fades inland/out

# --- Aggregates kept incrementally ---------------------------------------
var land_cells: int = 0
var water_cells: int = 0
var burning_cells: PackedInt32Array = PackedInt32Array()
var wet_cells: PackedInt32Array = PackedInt32Array()

## Cells whose albedo changed and need re-baking into the render texture.
var dirty_cells: PackedInt32Array = PackedInt32Array()
var full_redraw: bool = true

func _init(width: int = GameConfig.WORLD_W, height: int = GameConfig.WORLD_H) -> void:
	w = width
	h = height
	var n := w * h
	terrain = PackedByteArray(); terrain.resize(n)
	biome = PackedByteArray(); biome.resize(n)
	elevation = PackedFloat32Array(); elevation.resize(n)
	moisture = PackedFloat32Array(); moisture.resize(n)
	temperature = PackedFloat32Array(); temperature.resize(n)
	base_temp = PackedFloat32Array(); base_temp.resize(n)
	veg = PackedFloat32Array(); veg.resize(n)
	fire = PackedFloat32Array(); fire.resize(n)
	water = PackedFloat32Array(); water.resize(n)
	snow = PackedFloat32Array(); snow.resize(n)
	shade = PackedByteArray(); shade.resize(n)
	variation = PackedByteArray(); variation.resize(n)
	shore = PackedByteArray(); shore.resize(n)

# --------------------------------------------------------------------------
# Indexing
# --------------------------------------------------------------------------
func idx(x: int, y: int) -> int:
	return y * w + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h

func clamp_x(x: int) -> int:
	return clampi(x, 0, w - 1)

func clamp_y(y: int) -> int:
	return clampi(y, 0, h - 1)

func idx_at(pos: Vector2) -> int:
	return clamp_y(int(pos.y)) * w + clamp_x(int(pos.x))

func terrain_at(pos: Vector2) -> int:
	return terrain[idx_at(pos)]

# --------------------------------------------------------------------------
# Mutation
# --------------------------------------------------------------------------
## Single entry point for terrain changes so bookkeeping can never be skipped.
func set_terrain(i: int, t: int) -> void:
	var old: int = terrain[i]
	if old == t:
		return
	if Terrain.is_water(old) and not Terrain.is_water(t):
		water_cells -= 1
		land_cells += 1
	elif not Terrain.is_water(old) and Terrain.is_water(t):
		water_cells += 1
		land_cells -= 1
	terrain[i] = t
	if Terrain.is_water(t) or t == Terrain.T.LAVA:
		veg[i] = 0.0
		fire[i] = 0.0
	veg[i] = minf(veg[i], Terrain.FERTILITY[t])
	mark_dirty(i)
	_refresh_shore_around(i)

func mark_dirty(i: int) -> void:
	dirty_cells.append(i)

func _refresh_shore_around(i: int) -> void:
	var cx := i % w
	var cy := int(i / w)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := cx + dx
			var y := cy + dy
			if not in_bounds(x, y):
				continue
			var j := y * w + x
			shore[j] = _compute_shore(x, y)
			dirty_cells.append(j)

func _compute_shore(x: int, y: int) -> int:
	var i := y * w + x
	var here := Terrain.is_water(terrain[i])
	var best := 0
	for r in range(1, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var nx := x + dx
				var ny := y + dy
				if not in_bounds(nx, ny):
					continue
				if Terrain.is_water(terrain[ny * w + nx]) != here:
					best = maxi(best, 255 - (r - 1) * 110)
	return best

func recompute_shore() -> void:
	for y in h:
		for x in w:
			shore[y * w + x] = _compute_shore(x, y)

## Baked hillshade from the elevation gradient — this is what gives the map its
## sense of relief at a glance.
func recompute_shade() -> void:
	for y in h:
		for x in w:
			var i := y * w + x
			var xl := elevation[y * w + clamp_x(x - 1)]
			var xr := elevation[y * w + clamp_x(x + 1)]
			var yu := elevation[clamp_y(y - 1) * w + x]
			var yd := elevation[clamp_y(y + 1) * w + x]
			# Light from the north-west.
			var slope := (xl - xr) * 0.5 + (yu - yd) * 0.5
			var s := clampf(0.5 + slope * 7.0, 0.0, 1.0)
			shade[i] = int(s * 255.0)

# --------------------------------------------------------------------------
# Presentation
# --------------------------------------------------------------------------
## Final baked albedo of a cell (the shader adds animation and lighting).
func cell_color(i: int) -> Color:
	var t: int = terrain[i]
	var c: Color = Terrain.COLORS[t]
	if Terrain.is_water(t):
		# Depth gradient: shallow water reads warm and translucent.
		var depth := clampf((GameConfig.SEA_LEVEL - elevation[i]) / 0.22, 0.0, 1.0)
		c = Terrain.COLORS[Terrain.T.SHALLOW].lerp(Terrain.COLORS[Terrain.T.DEEP_WATER], depth)
	else:
		# Vegetation greens up fertile ground.
		var f: float = Terrain.FERTILITY[t]
		if f > 0.2:
			var v := clampf(veg[i] / maxf(0.2, f), 0.0, 1.0)
			c = c.lerp(Terrain.COLORS[Terrain.T.LUSH], v * 0.55)
		var sn := snow[i]
		if sn > 0.01:
			c = c.lerp(Terrain.COLORS[Terrain.T.SNOW], clampf(sn, 0.0, 0.92))
		var wl := water[i]
		if wl > 0.02:
			c = c.lerp(Terrain.COLORS[Terrain.T.SHALLOW], clampf(wl * 0.8, 0.0, 0.72))
	# Hillshade + per-cell jitter.
	var sh := 0.80 + (float(shade[i]) / 255.0) * 0.42
	var jit := (float(variation[i]) / 255.0 - 0.5) * 0.11
	if Terrain.is_water(t):
		sh = 0.94 + (float(shade[i]) / 255.0) * 0.12
		jit *= 0.5
	var m := sh + jit
	return Color(clampf(c.r * m, 0.0, 1.0), clampf(c.g * m, 0.0, 1.0), clampf(c.b * m, 0.0, 1.0), 1.0)

## RGBA payload consumed by the terrain shader.
## R: fire, G: shoreline proximity, B: vegetation, A: material class.
func cell_data(i: int) -> Color:
	var t: int = terrain[i]
	var mat := Terrain.mat_flag(t)
	if snow[i] > 0.45 and not Terrain.is_water(t):
		mat = Terrain.MAT_SNOW
	return Color(
		clampf(fire[i], 0.0, 1.0),
		float(shore[i]) / 255.0,
		clampf(veg[i], 0.0, 1.0),
		mat)

# --------------------------------------------------------------------------
# Queries used by the simulation
# --------------------------------------------------------------------------
func fertility_at(i: int) -> float:
	return Terrain.FERTILITY[terrain[i]]

## Removes up to `amount` biomass from a cell, returning what was actually eaten.
func consume_veg(i: int, amount: float) -> float:
	var have := veg[i]
	if have <= 0.0:
		return 0.0
	var take := minf(have, amount)
	veg[i] = have - take
	mark_dirty(i)
	return take

func is_drinkable(i: int) -> bool:
	return Terrain.is_water(terrain[i]) or water[i] > 0.08 or snow[i] > 0.2

func add_water(i: int, amount: float) -> void:
	if Terrain.is_water(terrain[i]):
		return
	var before := water[i]
	water[i] = clampf(before + amount, 0.0, 1.0)
	if before <= 0.02 and water[i] > 0.02:
		wet_cells.append(i)
	mark_dirty(i)

func ignite(i: int, strength: float = 0.6) -> bool:
	var t: int = terrain[i]
	if Terrain.FLAMMABILITY[t] <= 0.01:
		return false
	if water[i] > 0.25 or snow[i] > 0.35:
		return false
	if veg[i] < 0.06 and t != Terrain.T.LAVA:
		return false
	if fire[i] > 0.05:
		return false
	fire[i] = strength
	burning_cells.append(i)
	mark_dirty(i)
	return true
