class_name SpatialGrid
extends RefCounted
## Uniform-grid spatial hash over the world, rebuilt each simulation tick.
##
## Rebuilding 1k buckets + ~900 entries costs far less than maintaining
## incremental membership, and it can never drift out of sync. Queries fill a
## caller-visible buffer so the hot path allocates nothing.

var _cols: int
var _rows: int
var _cell: int
var _buckets: Array[PackedInt32Array] = []

## Reusable output buffer for queries (do not hold across queries).
var result: PackedInt32Array = PackedInt32Array()

func _init(world_w: int, world_h: int, cell_size: int) -> void:
	_cell = maxi(1, cell_size)
	_cols = int(ceil(float(world_w) / float(_cell)))
	_rows = int(ceil(float(world_h) / float(_cell)))
	_buckets.resize(_cols * _rows)
	for i in _buckets.size():
		_buckets[i] = PackedInt32Array()
	result.resize(0)

func clear() -> void:
	for i in _buckets.size():
		_buckets[i].resize(0)

func insert(id: int, x: float, y: float) -> void:
	var cx := clampi(int(x) / _cell, 0, _cols - 1)
	var cy := clampi(int(y) / _cell, 0, _rows - 1)
	_buckets[cy * _cols + cx].append(id)

## Fills `result` with every id inside the bucket neighbourhood covering
## `radius`, and returns it. Callers must still do an exact distance test.
func query(x: float, y: float, radius: float) -> PackedInt32Array:
	result.resize(0)
	var r := int(ceil(radius / float(_cell)))
	var cx := clampi(int(x) / _cell, 0, _cols - 1)
	var cy := clampi(int(y) / _cell, 0, _rows - 1)
	var y0 := maxi(0, cy - r)
	var y1 := mini(_rows - 1, cy + r)
	var x0 := maxi(0, cx - r)
	var x1 := mini(_cols - 1, cx + r)
	for gy in range(y0, y1 + 1):
		var row := gy * _cols
		for gx in range(x0, x1 + 1):
			var b := _buckets[row + gx]
			if b.size() > 0:
				result.append_array(b)
	return result

## Number of entries in the bucket containing a point (cheap density probe).
func local_density(x: float, y: float) -> int:
	var cx := clampi(int(x) / _cell, 0, _cols - 1)
	var cy := clampi(int(y) / _cell, 0, _rows - 1)
	return _buckets[cy * _cols + cx].size()

func bucket_counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(_buckets.size())
	for i in _buckets.size():
		out[i] = _buckets[i].size()
	return out

func dims() -> Vector2i:
	return Vector2i(_cols, _rows)
