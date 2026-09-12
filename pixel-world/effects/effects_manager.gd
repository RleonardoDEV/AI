class_name EffectsManager
extends Node2D
## Particles, ambient life and impact feedback.
##
## Two pools with different blend modes: opaque pixels for debris, dust, rain
## and snow; an additive pool for embers, glows, flashes and shockwaves. Both
## run on real time and are hard-capped, so effects never threaten frame rate.
## Ambient emitters are what make the world feel alive when nothing is
## happening — drifting motes, fireflies after dark, birds crossing the sky.

enum FX { IGNITE, BURN, SPLASH, BLOOM, DUST, FROST, GUST, METEOR, ERUPT, SPAWN, LIGHTNING }

const BIRD_FLOCKS: int = 3
const BIRDS_PER_FLOCK: int = 6

var pool: ParticlePool
var glow_pool: ParticlePool
var glow_tex: ImageTexture

var _opaque_layer: Node2D
var _add_layer: Node2D
var _wind: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _view: Rect2 = Rect2()
var _rain: float = 0.0
var _snow: float = 0.0
var _night: float = 0.0
var _budget_scale: float = 1.0

# Ambient birds: position, velocity, flock phase.
var _bird_pos: PackedVector2Array = PackedVector2Array()
var _bird_vel: PackedVector2Array = PackedVector2Array()
var _bird_phase: PackedFloat32Array = PackedFloat32Array()
var _bird_alive: PackedByteArray = PackedByteArray()
var _bird_timer: float = 4.0

var _mote_timer: float = 0.0
var _firefly_timer: float = 0.0
var _rain_timer: float = 0.0

func _ready() -> void:
	pool = ParticlePool.new(GameConfig.MAX_PARTICLES)
	glow_pool = ParticlePool.new(int(GameConfig.MAX_PARTICLES * 0.6))
	glow_tex = PixelArt.build_glow(48, 2.2)

	_opaque_layer = Node2D.new()
	_opaque_layer.name = "Opaque"
	_opaque_layer.draw.connect(_draw_opaque)
	add_child(_opaque_layer)

	_add_layer = Node2D.new()
	_add_layer.name = "Additive"
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_add_layer.material = mat
	_add_layer.draw.connect(_draw_additive)
	add_child(_add_layer)

	var n := BIRD_FLOCKS * BIRDS_PER_FLOCK
	_bird_pos.resize(n)
	_bird_vel.resize(n)
	_bird_phase.resize(n)
	_bird_alive.resize(n)

	EventBus.fx_burst.connect(_on_fx)

func set_environment(wind: Vector2, rain: float, snow: float, night: float, view: Rect2) -> void:
	_wind = wind
	_rain = rain
	_snow = snow
	_night = night
	_view = view

## Drops effect density when the simulation is racing (nobody can see it anyway).
func set_budget(scale: float) -> void:
	_budget_scale = clampf(scale, 0.15, 1.0)

func clear_all() -> void:
	pool.clear()
	glow_pool.clear()
	for i in _bird_alive.size():
		_bird_alive[i] = 0

# --------------------------------------------------------------------------
# Per-frame
# --------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	pool.update(delta, _wind * 1.2)
	glow_pool.update(delta, _wind * 0.7)
	if Config.particles_enabled:
		_ambient(delta)
	_update_birds(delta)
	_opaque_layer.queue_redraw()
	_add_layer.queue_redraw()

func _draw_opaque() -> void:
	pool.draw_into(_opaque_layer, glow_tex)
	_draw_birds(_opaque_layer)

func _draw_additive() -> void:
	glow_pool.draw_into(_add_layer, glow_tex)

# --------------------------------------------------------------------------
# Ambient life
# --------------------------------------------------------------------------
func _ambient(delta: float) -> void:
	var rng := _rng()
	var v := _view
	# --- floating motes / pollen -----------------------------------------
	_mote_timer -= delta
	if _mote_timer <= 0.0:
		_mote_timer = 0.055 / _budget_scale
		var p := Vector2(rng.randf_range(v.position.x, v.end.x), rng.randf_range(v.position.y, v.end.y))
		var warm := Color(0.95, 0.92, 0.72, 0.34)
		pool.emit(p, _wind * 1.6 + Vector2(rng.randfn(0.0, 0.25), rng.randfn(0.0, 0.18)),
				rng.randf_range(2.5, 6.0), rng.randf_range(0.3, 0.75), warm,
				ParticlePool.Kind.PIXEL, 0.25, -0.05)
	# --- fireflies after dark --------------------------------------------
	if _night > 0.45:
		_firefly_timer -= delta
		if _firefly_timer <= 0.0:
			_firefly_timer = 0.16 / _budget_scale
			var p2 := Vector2(rng.randf_range(v.position.x, v.end.x), rng.randf_range(v.position.y, v.end.y))
			glow_pool.emit(p2, Vector2(rng.randfn(0.0, 0.5), rng.randfn(0.0, 0.4)),
					rng.randf_range(1.4, 3.4), rng.randf_range(1.6, 3.2),
					Color(0.75, 1.0, 0.42, 0.55), ParticlePool.Kind.GLOW, 0.8, -0.1)
	# --- rain / snow ------------------------------------------------------
	if Config.weather_fx_enabled and (_rain > 0.02 or _snow > 0.02):
		_rain_timer -= delta
		if _rain_timer <= 0.0:
			_rain_timer = 0.012 / _budget_scale
			var burst := int(clampf((_rain + _snow) * 7.0, 1.0, 9.0))
			for k in burst:
				var p3 := Vector2(rng.randf_range(v.position.x, v.end.x),
						rng.randf_range(v.position.y, v.end.y))
				if _snow > 0.02:
					pool.emit(p3, Vector2(_wind.x * 3.0 + rng.randfn(0.0, 0.6), rng.randf_range(1.6, 3.2)),
							rng.randf_range(1.2, 2.6), rng.randf_range(0.35, 0.75),
							Color(0.95, 0.97, 1.0, 0.85), ParticlePool.Kind.PIXEL, 0.4, 0.4)
				else:
					pool.emit(p3, Vector2(_wind.x * 6.0, rng.randf_range(26.0, 40.0)),
							0.22, rng.randf_range(1.4, 2.6),
							Color(0.66, 0.80, 0.95, 0.5), ParticlePool.Kind.STREAK, 0.0, 20.0)

func splash(at: Vector2, strength: float = 1.0) -> void:
	var rng := _rng()
	for k in int(3.0 * strength):
		pool.emit(at, Vector2(rng.randfn(0.0, 1.6), rng.randfn(0.0, 1.6) - 1.2),
				rng.randf_range(0.2, 0.45), rng.randf_range(0.35, 0.7),
				Color(0.72, 0.88, 1.0, 0.8), ParticlePool.Kind.PIXEL, 2.0, 5.0)

## Fire emission driven by the fire system's event lists.
func fire_events(sparks: PackedVector2Array, smokes: PackedVector2Array) -> void:
	if not Config.particles_enabled:
		return
	var rng := _rng()
	var limit := int(10.0 * _budget_scale) + 1
	for k in mini(sparks.size(), limit):
		var p: Vector2 = sparks[k]
		glow_pool.emit(p, Vector2(rng.randfn(0.0, 1.1), -rng.randf_range(1.4, 3.6)),
				rng.randf_range(0.5, 1.2), rng.randf_range(1.6, 3.4),
				Color(1.0, 0.62, 0.22, 0.9), ParticlePool.Kind.GLOW, 1.0, -0.9)
	for k in mini(smokes.size(), limit):
		var p2: Vector2 = smokes[k]
		pool.emit(p2, Vector2(rng.randfn(0.0, 0.5), -rng.randf_range(0.8, 1.8)),
				rng.randf_range(1.6, 3.6), rng.randf_range(1.0, 2.4),
				Color(0.22, 0.20, 0.22, 0.42), ParticlePool.Kind.PIXEL, 0.35, -0.25)

# --------------------------------------------------------------------------
# Birds
# --------------------------------------------------------------------------
func _update_birds(delta: float) -> void:
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		_bird_timer = randf_range(9.0, 26.0)
		_spawn_flock()
	for i in _bird_pos.size():
		if _bird_alive[i] == 0:
			continue
		var v: Vector2 = _bird_vel[i]
		_bird_phase[i] += delta * 9.0
		# Gentle sinusoidal wander perpendicular to travel.
		var perp := Vector2(-v.y, v.x).normalized()
		_bird_pos[i] += (v + perp * sin(_bird_phase[i] * 0.35) * 1.6) * delta
		var p: Vector2 = _bird_pos[i]
		if p.x < -30.0 or p.y < -30.0 or p.x > 320.0 or p.y > 320.0:
			_bird_alive[i] = 0

func _spawn_flock() -> void:
	var rng := _rng()
	var base := -1
	for f in BIRD_FLOCKS:
		var idx := f * BIRDS_PER_FLOCK
		if _bird_alive[idx] == 0:
			base = idx
			break
	if base < 0:
		return
	var from_left := rng.randf() < 0.5
	var start := Vector2(-14.0 if from_left else 270.0, rng.randf_range(20.0, 236.0))
	var dir := Vector2(1.0 if from_left else -1.0, rng.randfn(0.0, 0.25)).normalized()
	var spd := rng.randf_range(7.0, 13.0)
	var n := rng.randi_range(3, BIRDS_PER_FLOCK)
	for k in BIRDS_PER_FLOCK:
		var i := base + k
		if k >= n:
			_bird_alive[i] = 0
			continue
		# V formation offsets.
		var row := float((k + 1) / 2)
		var side := 1.0 if k % 2 == 0 else -1.0
		var off := Vector2(-row * 2.4, side * row * 1.8)
		_bird_pos[i] = start + off.rotated(dir.angle())
		_bird_vel[i] = dir * spd
		_bird_phase[i] = rng.randf() * TAU
		_bird_alive[i] = 1

func _draw_birds(ci: CanvasItem) -> void:
	for i in _bird_pos.size():
		if _bird_alive[i] == 0:
			continue
		var p: Vector2 = _bird_pos[i]
		# Wing beat: the silhouette alternates between a dash and a dot.
		var beat := sin(_bird_phase[i]) > 0.0
		var col := Color(0.10, 0.11, 0.14, 0.75 - _night * 0.35)
		# Shadow on the ground below.
		ci.draw_rect(Rect2(p + Vector2(0.8, 2.2), Vector2(0.8, 0.5)), Color(0, 0, 0, 0.16), true)
		if beat:
			ci.draw_rect(Rect2(p - Vector2(1.1, 0.25), Vector2(2.2, 0.5)), col, true)
		else:
			ci.draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), col, true)

# --------------------------------------------------------------------------
# Impact effects
# --------------------------------------------------------------------------
func _on_fx(at: Vector2, kind: int, strength: float) -> void:
	var rng := _rng()
	match kind:
		FX.IGNITE:
			for k in 8:
				glow_pool.emit(at + Vector2(rng.randfn(0.0, strength * 0.4), rng.randfn(0.0, strength * 0.4)),
						Vector2(rng.randfn(0.0, 1.5), -rng.randf_range(1.0, 3.0)),
						rng.randf_range(0.4, 1.1), rng.randf_range(2.0, 4.0),
						Color(1.0, 0.55, 0.18, 0.9), ParticlePool.Kind.GLOW, 1.0, -0.8)
		FX.BURN:
			for k in 10:
				glow_pool.emit(at, Vector2(rng.randfn(0.0, 2.0), -rng.randf_range(1.5, 4.0)),
						rng.randf_range(0.5, 1.4), rng.randf_range(1.4, 3.0),
						Color(1.0, 0.68, 0.28, 0.85), ParticlePool.Kind.GLOW, 1.2, -0.6)
			for k in 6:
				pool.emit(at, Vector2(rng.randfn(0.0, 1.0), -rng.randf_range(0.8, 2.0)),
						rng.randf_range(1.5, 3.0), rng.randf_range(1.0, 2.0),
						Color(0.20, 0.18, 0.20, 0.45), ParticlePool.Kind.PIXEL, 0.4, -0.2)
		FX.SPLASH:
			glow_pool.emit(at, Vector2.ZERO, 0.7, strength * 2.2,
					Color(0.55, 0.85, 1.0, 0.8), ParticlePool.Kind.RING, 0.0, 0.0)
			for k in int(clampf(strength, 4.0, 22.0)):
				pool.emit(at, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(2.0, 9.0),
						rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 1.0),
						Color(0.75, 0.90, 1.0, 0.85), ParticlePool.Kind.PIXEL, 2.4, 6.0)
		FX.BLOOM:
			for k in int(clampf(strength * 1.6, 6.0, 26.0)):
				var c := Color(0.55 + rng.randf() * 0.3, 1.0, 0.5, 0.8)
				glow_pool.emit(at + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * strength,
						Vector2(rng.randfn(0.0, 0.6), -rng.randf_range(0.5, 2.0)),
						rng.randf_range(0.6, 1.6), rng.randf_range(1.2, 2.6), c,
						ParticlePool.Kind.GLOW, 1.0, -0.4)
		FX.DUST:
			for k in int(clampf(strength * 1.4, 6.0, 24.0)):
				pool.emit(at + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * strength,
						Vector2(rng.randfn(0.0, 2.0), rng.randfn(0.0, 2.0)),
						rng.randf_range(0.5, 1.4), rng.randf_range(0.6, 1.5),
						Color(0.62, 0.57, 0.48, 0.6), ParticlePool.Kind.PIXEL, 2.0, 1.5)
		FX.FROST:
			for k in int(clampf(strength * 1.5, 6.0, 26.0)):
				glow_pool.emit(at + Vector2.from_angle(rng.randf() * TAU) * rng.randf() * strength,
						Vector2(rng.randfn(0.0, 0.8), rng.randfn(0.0, 0.8)),
						rng.randf_range(0.8, 2.0), rng.randf_range(1.0, 2.4),
						Color(0.72, 0.92, 1.0, 0.7), ParticlePool.Kind.GLOW, 1.4, 0.0)
		FX.GUST:
			for k in 16:
				var d := Vector2.from_angle(rng.randf() * TAU)
				pool.emit(at + d * rng.randf() * strength, d * rng.randf_range(4.0, 14.0),
						rng.randf_range(0.3, 0.9), rng.randf_range(1.0, 2.2),
						Color(0.80, 0.78, 0.70, 0.4), ParticlePool.Kind.STREAK, 1.2, 0.0)
		FX.METEOR:
			glow_pool.emit(at, Vector2.ZERO, 1.1, strength * 3.4,
					Color(1.0, 0.82, 0.45, 0.95), ParticlePool.Kind.RING, 0.0, 0.0)
			glow_pool.emit(at, Vector2.ZERO, 0.9, strength * 5.0,
					Color(1.0, 0.55, 0.2, 0.85), ParticlePool.Kind.GLOW, 0.0, 0.0)
			for k in 34:
				var d2 := Vector2.from_angle(rng.randf() * TAU)
				pool.emit(at, d2 * rng.randf_range(6.0, 26.0), rng.randf_range(0.5, 1.6),
						rng.randf_range(0.7, 2.0), Color(0.35, 0.28, 0.24, 0.85),
						ParticlePool.Kind.PIXEL, 1.6, 4.0)
			for k in 22:
				glow_pool.emit(at, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, 16.0),
						rng.randf_range(0.6, 1.8), rng.randf_range(2.0, 5.0),
						Color(1.0, 0.62, 0.22, 0.9), ParticlePool.Kind.GLOW, 1.4, -0.5)
			for k in 16:
				pool.emit(at + Vector2(rng.randfn(0.0, 3.0), rng.randfn(0.0, 3.0)),
						Vector2(rng.randfn(0.0, 1.2), -rng.randf_range(1.5, 4.0)),
						rng.randf_range(2.5, 5.5), rng.randf_range(2.0, 4.5),
						Color(0.24, 0.22, 0.24, 0.5), ParticlePool.Kind.PIXEL, 0.3, -0.3)
		FX.ERUPT:
			for k in 26:
				glow_pool.emit(at, Vector2(rng.randfn(0.0, 3.0), -rng.randf_range(3.0, 11.0)),
						rng.randf_range(0.8, 2.2), rng.randf_range(2.0, 4.6),
						Color(1.0, 0.48, 0.14, 0.92), ParticlePool.Kind.GLOW, 0.7, 3.2)
			for k in 20:
				pool.emit(at, Vector2(rng.randfn(0.0, 2.0), -rng.randf_range(2.0, 7.0)),
						rng.randf_range(3.0, 6.5), rng.randf_range(2.0, 4.0),
						Color(0.18, 0.16, 0.18, 0.5), ParticlePool.Kind.PIXEL, 0.25, -0.4)
		FX.SPAWN:
			glow_pool.emit(at, Vector2.ZERO, 0.6, strength * 2.0,
					Color(0.7, 1.0, 0.8, 0.8), ParticlePool.Kind.RING, 0.0, 0.0)
			for k in 10:
				glow_pool.emit(at, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, 4.0),
						rng.randf_range(0.4, 1.0), rng.randf_range(1.2, 2.4),
						Color(0.75, 1.0, 0.85, 0.7), ParticlePool.Kind.GLOW, 1.6, 0.0)
		FX.LIGHTNING:
			glow_pool.emit(at, Vector2.ZERO, 0.35, strength * 3.0,
					Color(0.9, 0.95, 1.0, 0.95), ParticlePool.Kind.GLOW, 0.0, 0.0)
			for k in 12:
				glow_pool.emit(at, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 14.0),
						rng.randf_range(0.2, 0.5), rng.randf_range(1.0, 2.4),
						Color(0.95, 0.98, 1.0, 0.9), ParticlePool.Kind.STREAK, 1.0, 0.0)

var _rng_inst: RandomNumberGenerator = null
func _rng() -> RandomNumberGenerator:
	if _rng_inst == null:
		_rng_inst = RandomNumberGenerator.new()
		_rng_inst.randomize()
	return _rng_inst
