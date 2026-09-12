class_name FloraSystem
extends RefCounted
## Trees and shrubs: pooled, chunk-updated, and rendered as sprites on top of
## the terrain so the world has vertical detail and parallax-free sway.
##
## Flora is part of the ecology, not decoration: canopies grow through stages,
## burn away in fires, seed nearby fertile ground, and their density is what
## makes forests read as forests from a distance.

const SLICES: int = 8

var pos: PackedVector2Array = PackedVector2Array()
var variant: PackedByteArray = PackedByteArray()
var stage: PackedByteArray = PackedByteArray()
var kind: PackedByteArray = PackedByteArray()       # 0 tree, 1 shrub
var growth: PackedFloat32Array = PackedFloat32Array()
var active: PackedByteArray = PackedByteArray()
var phase: PackedFloat32Array = PackedFloat32Array()  # sway offset
var count: int = 0
var capacity: int = GameConfig.MAX_TREES

var _cursor: int = 0
var _free: PackedInt32Array = PackedInt32Array()

func _init(cap: int = GameConfig.MAX_TREES) -> void:
	capacity = cap
	pos.resize(cap)
	variant.resize(cap)
	stage.resize(cap)
	kind.resize(cap)
	growth.resize(cap)
	active.resize(cap)
	phase.resize(cap)
	_free.resize(cap)
	for i in cap:
		_free[cap - 1 - i] = i

func clear() -> void:
	# Resize first: the free list shrinks as plants are allocated, so filling
	# it before restoring its length writes out of bounds.
	_free.resize(capacity)
	for i in capacity:
		active[i] = 0
		_free[capacity - 1 - i] = i
	count = 0

func add(at: Vector2, var_id: int, stage_id: int, kind_id: int, rng: RandomNumberGenerator) -> int:
	if _free.is_empty():
		return -1
	var i: int = _free[_free.size() - 1]
	_free.remove_at(_free.size() - 1)
	pos[i] = at
	variant[i] = var_id
	stage[i] = stage_id
	kind[i] = kind_id
	growth[i] = float(stage_id) / float(PixelArt.TREE_STAGES - 1)
	active[i] = 1
	phase[i] = rng.randf() * TAU
	count += 1
	return i

func remove(i: int) -> void:
	if active[i] == 0:
		return
	active[i] = 0
	_free.append(i)
	count -= 1

func populate_from_gen(rng: RandomNumberGenerator) -> void:
	clear()
	for f in WorldGen.last_flora:
		add(f["pos"], int(f["variant"]), int(f["stage"]), int(f["kind"]), rng)

## Chunked growth / fire / seeding sweep.
func update(ctx: SimContext, dt: float) -> void:
	var world := ctx.world
	var slice := int(capacity / SLICES)
	var start := _cursor
	var end: int = mini(capacity, start + slice)
	# Each cell is visited once per SLICES calls, so it advances by dt * SLICES.
	var eff_dt := dt * float(SLICES)
	var rng := ctx.rng

	for i in range(start, end):
		if active[i] == 0:
			continue
		var p := pos[i]
		var j := world.idx_at(p)
		# Burned by fire, drowned by flooding, or buried by lava.
		if world.fire[j] > 0.05:
			if rng.randf() < eff_dt * 0.7:
				remove(i)
				EventBus.fx_burst.emit(p, 1, 0.8)
				continue
		var terr: int = world.terrain[j]
		if Terrain.is_water(terr) or terr == Terrain.T.LAVA:
			remove(i)
			continue
		var fert: float = Terrain.FERTILITY[terr]
		if fert < 0.12:
			# Wrong ground: slowly dies back.
			growth[i] -= eff_dt * 0.02
			if growth[i] <= 0.0:
				remove(i)
			continue
		# Grow with available moisture and warmth.
		var temp_ok: float = 1.0 - clampf(absf(world.temperature[j] - 20.0) / 32.0, 0.0, 1.0)
		growth[i] = clampf(growth[i] + eff_dt * 0.0045 * temp_ok * (0.3 + world.moisture[j]), 0.0, 1.0)
		var st := int(growth[i] * float(PixelArt.TREE_STAGES - 1) + 0.001)
		stage[i] = clampi(st, 0, PixelArt.TREE_STAGES - 1)
		# A mature canopy shades and enriches its own cell.
		if kind[i] == 0 and stage[i] >= 2:
			world.veg[j] = minf(fert, world.veg[j] + eff_dt * 0.004)
		# Seeding: mature plants occasionally sow a neighbour.
		if count < capacity - 4 and growth[i] > 0.75 and rng.randf() < eff_dt * 0.010:
			var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, 7.0)
			var np := p + off
			if np.x > 1.0 and np.y > 1.0 and np.x < float(world.w) - 1.0 and np.y < float(world.h) - 1.0:
				var nj := world.idx_at(np)
				var nfert: float = Terrain.FERTILITY[world.terrain[nj]]
				if nfert > 0.35 and world.veg[nj] > nfert * 0.45 and world.fire[nj] <= 0.0:
					add(np, variant[i], 0, kind[i], rng)

	_cursor = end
	if _cursor >= capacity:
		_cursor = 0

func serialize() -> Dictionary:
	# Only live entries are stored, as parallel arrays.
	var p := PackedVector2Array()
	var v := PackedByteArray()
	var s := PackedByteArray()
	var k := PackedByteArray()
	var g := PackedFloat32Array()
	for i in capacity:
		if active[i] == 0:
			continue
		p.append(pos[i])
		v.append(variant[i])
		s.append(stage[i])
		k.append(kind[i])
		g.append(growth[i])
	return {"pos": p, "var": v, "stage": s, "kind": k, "growth": g}

func deserialize(d: Dictionary, rng: RandomNumberGenerator) -> void:
	clear()
	var p := PackedVector2Array(d.get("pos", PackedVector2Array()))
	var v := PackedByteArray(d.get("var", PackedByteArray()))
	var s := PackedByteArray(d.get("stage", PackedByteArray()))
	var k := PackedByteArray(d.get("kind", PackedByteArray()))
	var g := PackedFloat32Array(d.get("growth", PackedFloat32Array()))
	for i in p.size():
		var idx := add(p[i], v[i] if i < v.size() else 0, s[i] if i < s.size() else 1,
				k[i] if i < k.size() else 0, rng)
		if idx >= 0 and i < g.size():
			growth[idx] = g[i]
