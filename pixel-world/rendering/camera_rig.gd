class_name CameraRig
extends Camera2D
## Touch camera: one-finger pan (when no tool is armed), two-finger pinch zoom,
## mouse wheel on desktop, inertial drift and clamping to the world bounds.
## Zoom is smoothed toward a target and snapped to whole pixels at high
## magnification so the art stays pixel-perfect.

var world_w: float = 256.0
var world_h: float = 256.0

var target_zoom: float = GameConfig.ZOOM_DEFAULT
var _velocity: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _touches: Dictionary = {}
var _pinch_start_dist: float = 0.0
var _pinch_start_zoom: float = 1.0
var _pinch_mid_world: Vector2 = Vector2.ZERO

## When false, one-finger drags are left for the active world tool.
var pan_with_one_finger: bool = true

func setup(w: float, h: float) -> void:
	world_w = w
	world_h = h
	zoom = Vector2.ONE * GameConfig.ZOOM_DEFAULT
	target_zoom = GameConfig.ZOOM_DEFAULT
	position = Vector2(w * 0.5, h * 0.5)

func _ready() -> void:
	EventBus.camera_focus_requested.connect(_on_focus_requested)

func _on_focus_requested(world_pos: Vector2, z: float) -> void:
	position = world_pos
	if z > 0.0:
		target_zoom = clampf(z, GameConfig.ZOOM_MIN, GameConfig.ZOOM_MAX)
	_velocity = Vector2.ZERO

## Frames the whole world.
func frame_world() -> void:
	var vp := get_viewport_rect().size
	var fit: float = minf(vp.x / world_w, vp.y / world_h)
	target_zoom = clampf(fit, GameConfig.ZOOM_MIN * 0.6, GameConfig.ZOOM_MAX)
	position = Vector2(world_w * 0.5, world_h * 0.5)
	_velocity = Vector2.ZERO

func screen_to_world(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touches[t.index] = t.position
			if _touches.size() == 2:
				_begin_pinch()
		else:
			_touches.erase(t.index)
			_pinch_start_dist = 0.0
			_dragging = false
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touches[d.index] = d.position
		if _touches.size() >= 2:
			_update_pinch()
		elif pan_with_one_finger:
			_dragging = true
			position -= d.relative / zoom.x
			_velocity = -d.relative / zoom.x * 12.0
			_clamp_position()
	elif event is InputEventMagnifyGesture:
		var m := event as InputEventMagnifyGesture
		_zoom_at(m.position, target_zoom * m.factor)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		position += pg.delta * 18.0 / zoom.x
		_clamp_position()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, target_zoom * 1.12)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, target_zoom / 1.12)

func _begin_pinch() -> void:
	var pts := _touch_points()
	if pts.size() < 2:
		return
	_pinch_start_dist = maxf(1.0, pts[0].distance_to(pts[1]))
	_pinch_start_zoom = target_zoom
	_pinch_mid_world = screen_to_world((pts[0] + pts[1]) * 0.5)

func _update_pinch() -> void:
	var pts := _touch_points()
	if pts.size() < 2 or _pinch_start_dist <= 0.0:
		return
	var dist := maxf(1.0, pts[0].distance_to(pts[1]))
	var mid := (pts[0] + pts[1]) * 0.5
	target_zoom = clampf(_pinch_start_zoom * (dist / _pinch_start_dist),
			GameConfig.ZOOM_MIN, GameConfig.ZOOM_MAX)
	# Keep the world point under the pinch centre pinned.
	zoom = Vector2.ONE * target_zoom
	var after := screen_to_world(mid)
	position += _pinch_mid_world - after
	_clamp_position()

func _touch_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for k in _touches.keys():
		out.append(_touches[k])
	return out

func _zoom_at(screen_pos: Vector2, new_zoom: float) -> void:
	var before := screen_to_world(screen_pos)
	target_zoom = clampf(new_zoom, GameConfig.ZOOM_MIN, GameConfig.ZOOM_MAX)
	zoom = Vector2.ONE * target_zoom
	var after := screen_to_world(screen_pos)
	position += before - after
	_clamp_position()

func _process(delta: float) -> void:
	# Smooth zoom, snapped to whole steps once magnified enough to matter.
	var z := zoom.x
	if absf(z - target_zoom) > 0.001:
		z = lerpf(z, target_zoom, clampf(delta * 12.0, 0.0, 1.0))
		zoom = Vector2.ONE * z
	# Inertial drift after a flick.
	if not _dragging and _velocity.length_squared() > 0.01:
		position += _velocity * delta
		_velocity *= pow(0.02, delta)
		_clamp_position()
	elif _dragging:
		_velocity = Vector2.ZERO

func _clamp_position() -> void:
	var vp := get_viewport_rect().size / zoom.x
	var half := vp * 0.5
	var min_x := minf(half.x, world_w * 0.5)
	var max_x := maxf(world_w - half.x, world_w * 0.5)
	var min_y := minf(half.y, world_h * 0.5)
	var max_y := maxf(world_h - half.y, world_h * 0.5)
	position.x = clampf(position.x, min_x, max_x)
	position.y = clampf(position.y, min_y, max_y)
