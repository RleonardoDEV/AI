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

## Cells whose *terrain or elevation* differs from what the generator would
## produce for this seed. Saving stores only these, so a world file is a seed
## plus a delta rather than a dump of the whole grid.
var modified: PackedInt32Array = PackedInt32Array()
var _modified_flag: PackedByteArray = PackedByteArray()

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
	_modified_flag = PackedByteArray(); _modified_flag.resize(n)

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
	mark_modified(i)
	if Terrain.is_water(t) or t == Terrain.T.LAVA:
		veg[i] = 0.0
		fire[i] = 0.0
	veg[i] = minf(veg[i], Terrain.FERTILITY[t])
	mark_dirty(i)
	if _bulk:
		var bx := i % w
		var by := int(i / w)
		_bulk_min.x = mini(_bulk_min.x, bx)
		_bulk_min.y = mini(_bulk_min.y, by)
		_bulk_max.x = maxi(_bulk_max.x, bx)
		_bulk_max.y = maxi(_bulk_max.y, by)
	else:
		_refresh_shore_around(i)

## Queues a cell for re-baking. If the queue grows past a quarter of the grid
## it is cheaper to rebake everything, and this also keeps the queue bounded
## when running headless (where nothing ever flushes it).
## Records a permanent change to the terrain at `i` (idempotent).
func mark_modified(i: int) -> void:
	if _modified_flag[i] == 0:
		_modified_flag[i] = 1
		modified.append(i)

func clear_modified() -> void:
	modified.resize(0)
	for i in _modified_flag.size():
		_modified_flag[i] = 0

## Bulk-edit mode: shoreline recomputation is deferred while a tool paints a
## whole region. Recomputing per cell made a single meteor impact cost hundreds
## of thousands of neighbourhood lookups and produced a visible frame hitch.
var _bulk: bool = false
var _bulk_min := Vector2i.ZERO
var _bulk_max := Vector2i.ZERO

func begin_bulk_edit() -> void:
	_bulk = true
	_bulk_min = Vector2i(w, h)
	_bulk_max = Vector2i(-1, -1)

func end_bulk_edit() -> void:
	_bulk = false
	if _bulk_max.x < 0:
		return
	var x0 := maxi(0, _bulk_min.x - 3)
	var y0 := maxi(0, _bulk_min.y - 3)
	var x1 := mini(w - 1, _bulk_max.x + 3)
	var y1 := mini(h - 1, _bulk_max.y + 3)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var j := y * w + x
			shore[j] = _compute_shore(x, y)
			mark_dirty(j)

func mark_dirty(i: int) -> void:
	if full_redraw:
		return
	if dirty_cells.size() > (w * h) >> 2:
		full_redraw = true
		dirty_cells.resize(0)
		return
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

## Drinkable includes *standing on the bank*: the baked shore band marks land
## cells at the waterline. Without this, land animals walk to the coast, are
## blocked by deep water they cannot enter, and die of thirst beside the sea.
func is_drinkable(i: int) -> bool:
	return Terrain.is_water(terrain[i]) or shore[i] >= 95 or water[i] > 0.08 or snow[i] > 0.2

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
