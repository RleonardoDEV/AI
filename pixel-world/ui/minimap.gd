extends PanelContainer
## World overview: terrain, creature density, fire, and the current viewport.
## Tapping it flies the camera there.
##
## The terrain layer is produced by downscaling the renderer's own albedo image
## in one engine-side resize (cheap) and refreshed on a timer; only the dynamic
## overlay is stamped per update.

const MAP_PX: int = 128
const REFRESH_TERRAIN: float = 1.0
const REFRESH_OVERLAY: float = 0.18

var sim: Simulation
var terrain_ref: TerrainRenderer

var _base: Image
var _img: Image
var _tex: ImageTexture
var _view: Rect2 = Rect2()
var _t_terrain: float = 99.0
var _t_overlay: float = 0.0
var _canvas: Control

func setup(simulation: Simulation, terrain: TerrainRenderer) -> void:
	sim = simulation
	terrain_ref = terrain
	add_theme_stylebox_override("panel", UITheme.panel(10, UITheme.BG_SOLID))
	_img = Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_input)
	add_child(_canvas)

func set_view(view: Rect2) -> void:
	_view = view

func _process(delta: float) -> void:
	if sim == null:
		return
	_t_terrain += delta
	_t_overlay += delta
	if _t_terrain >= REFRESH_TERRAIN:
		_t_terrain = 0.0
		_rebuild_base()
	if _t_overlay >= REFRESH_OVERLAY:
		_t_overlay = 0.0
		_rebuild_overlay()
		_canvas.queue_redraw()

func _rebuild_base() -> void:
	if terrain_ref == null or terrain_ref.albedo_img == null:
		return
	_base = terrain_ref.albedo_img.duplicate()
	_base.resize(MAP_PX, MAP_PX, Image.INTERPOLATE_NEAREST)

func _rebuild_overlay() -> void:
	if _base == null:
		_rebuild_base()
		if _base == null:
			return
	_img.blit_rect(_base, Rect2i(0, 0, MAP_PX, MAP_PX), Vector2i.ZERO)
	var sx := float(MAP_PX) / float(sim.world.w)
	var sy := float(MAP_PX) / float(sim.world.h)
	# Fire first, so creatures draw over it.
	var burning := sim.world.burning_cells
	var stride: int = maxi(1, int(burning.size() / 400) + 1)
	var k := 0
	while k < burning.size():
		var i: int = burning[k]
		k += stride
		var x := int(float(i % sim.world.w) * sx)
		var y := int(float(int(i / sim.world.w)) * sy)
		if x >= 0 and y >= 0 and x < MAP_PX and y < MAP_PX:
			_img.set_pixel(x, y, Color(1.0, 0.55, 0.18))
	# Creatures, coloured by trophic role.
	var ids := sim.entities.alive_ids
	var cstride: int = maxi(1, int(ids.size() / 600) + 1)
	var j := 0
	while j < ids.size():
		var c: Creature = sim.entities.creatures[ids[j]]
		j += cstride
		if not c.alive:
			continue
		var x2 := int(c.pos.x * sx)
		var y2 := int(c.pos.y * sy)
		if x2 < 0 or y2 < 0 or x2 >= MAP_PX or y2 >= MAP_PX:
			continue
		var col := Color(0.85, 0.55, 1.0)
		if c.diet > 0.62:
			col = Color(1.0, 0.35, 0.35)
		elif c.diet > 0.38:
			col = Color(1.0, 0.85, 0.35)
		# Brighten where animals overlap, so herds read as hot spots.
		var prev := _img.get_pixel(x2, y2)
		_img.set_pixel(x2, y2, prev.lerp(col, 0.85))
	_tex.update(_img)

func _draw_map() -> void:
	if _tex == null:
		return
	var r := Rect2(Vector2.ZERO, Vector2(MAP_PX, MAP_PX))
	_canvas.draw_texture_rect(_tex, r, false)
	# Current viewport outline.
	var sx := float(MAP_PX) / float(sim.world.w)
	var sy := float(MAP_PX) / float(sim.world.h)
	var vr := Rect2(_view.position.x * sx, _view.position.y * sy,
			_view.size.x * sx, _view.size.y * sy)
	_canvas.draw_rect(vr, Color(1, 1, 1, 0.85), false, 1.0)
	_canvas.draw_rect(r, Color(1, 1, 1, 0.14), false, 1.0)

func _on_input(event: InputEvent) -> void:
	var p := Vector2.INF
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		p = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		p = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		p = (event as InputEventScreenDrag).position
	if p == Vector2.INF:
		return
	var wx := p.x / float(MAP_PX) * float(sim.world.w)
	var wy := p.y / float(MAP_PX) * float(sim.world.h)
	EventBus.camera_focus_requested.emit(Vector2(wx, wy), -1.0)
	_canvas.accept_event()
