class_name ParticlePool
extends RefCounted
## Fixed-size, structure-of-arrays particle pool drawn by a single CanvasItem.
##
## Particles are presentation only: they run on *real* time, never allocate,
## and are silently dropped when the pool is full, so effects can never cost
## frame time beyond their budget.

enum Kind { PIXEL, GLOW, RING, STREAK }

var cap: int
var pos: PackedVector2Array
var vel: PackedVector2Array
var life: PackedFloat32Array
var life_max: PackedFloat32Array
var size: PackedFloat32Array
var col: PackedColorArray
var kind: PackedByteArray
var drag: PackedFloat32Array
var grav: PackedFloat32Array
var active: PackedByteArray
var count: int = 0
var _cursor: int = 0

func _init(capacity: int) -> void:
	cap = capacity
	pos = PackedVector2Array(); pos.resize(cap)
	vel = PackedVector2Array(); vel.resize(cap)
	life = PackedFloat32Array(); life.resize(cap)
	life_max = PackedFloat32Array(); life_max.resize(cap)
	size = PackedFloat32Array(); size.resize(cap)
	col = PackedColorArray(); col.resize(cap)
	kind = PackedByteArray(); kind.resize(cap)
	drag = PackedFloat32Array(); drag.resize(cap)
	grav = PackedFloat32Array(); grav.resize(cap)
	active = PackedByteArray(); active.resize(cap)

func clear() -> void:
	for i in cap:
		active[i] = 0
	count = 0

func emit(p: Vector2, v: Vector2, ttl: float, sz: float, c: Color,
		k: int = Kind.PIXEL, dg: float = 1.6, gv: float = 0.0) -> int:
	if count >= cap:
		return -1
	var slot := -1
	for step in cap:
		var i := (_cursor + step) % cap
		if active[i] == 0:
			slot = i
			break
	if slot < 0:
		return -1
	_cursor = (slot + 1) % cap
	pos[slot] = p
	vel[slot] = v
	life[slot] = ttl
	life_max[slot] = ttl
	size[slot] = sz
	col[slot] = c
	kind[slot] = k
	drag[slot] = dg
	grav[slot] = gv
	active[slot] = 1
	count += 1
	return slot

func update(dt: float, wind: Vector2) -> void:
	if count <= 0:
		return
	for i in cap:
		if active[i] == 0:
			continue
		var l := life[i] - dt
		if l <= 0.0:
			active[i] = 0
			count -= 1
			continue
		life[i] = l
		var v := vel[i]
		v += wind * dt * 2.2
		v.y += grav[i] * dt
		v *= 1.0 - clampf(drag[i] * dt, 0.0, 0.95)
		vel[i] = v
		pos[i] += v * dt

## Draws every live particle. `glow` is the radial texture used by GLOW kind.
func draw_into(ci: CanvasItem, glow: Texture2D) -> void:
	if count <= 0:
		return
	for i in cap:
		if active[i] == 0:
			continue
		var t: float = life[i] / maxf(0.0001, life_max[i])
		var c: Color = col[i]
		var a: float = c.a * clampf(t * 1.6, 0.0, 1.0)
		var s: float = size[i]
		var p: Vector2 = pos[i]
		match kind[i]:
			Kind.PIXEL:
				# Snapped to whole world texels to preserve the pixel grid.
				var q := Vector2(floor(p.x), floor(p.y))
				ci.draw_rect(Rect2(q, Vector2(s, s)), Color(c.r, c.g, c.b, a), true)
			Kind.GLOW:
				var r: float = s * (0.6 + (1.0 - t) * 0.9)
				ci.draw_texture_rect(glow, Rect2(p - Vector2(r, r) * 0.5, Vector2(r, r)),
						false, Color(c.r, c.g, c.b, a))
			Kind.RING:
				var rr: float = s * (1.0 - t) * 1.0 + s * 0.15
				ci.draw_arc(p, rr, 0.0, TAU, 22, Color(c.r, c.g, c.b, a), maxf(0.35, s * 0.06), false)
			Kind.STREAK:
				var dir: Vector2 = vel[i]
				if dir.length_squared() < 0.001:
					dir = Vector2.DOWN
				var tail: Vector2 = p - dir.normalized() * s
				ci.draw_line(p, tail, Color(c.r, c.g, c.b, a), maxf(0.3, s * 0.12))
