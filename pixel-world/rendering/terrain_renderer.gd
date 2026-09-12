class_name TerrainRenderer
extends Node2D
## Draws the entire world as a single shaded sprite: one texel per cell, one
## draw call. Cell changes are re-baked into the albedo/data images and
## uploaded at most once per frame, and only when something actually changed.

const SHADER_PATH := "res://rendering/shaders/terrain.gdshader"

var world: WorldData
var albedo_img: Image
var data_img: Image
var albedo_tex: ImageTexture
var data_tex: ImageTexture
var noise_tex: ImageTexture

var _sprite: Sprite2D
var _mat: ShaderMaterial
var _needs_upload: bool = false
var _time: float = 0.0
var _cloud_scroll: float = 0.0

func setup(w: WorldData, world_seed: int) -> void:
	world = w
	albedo_img = Image.create(w.w, w.h, false, Image.FORMAT_RGBA8)
	data_img = Image.create(w.w, w.h, false, Image.FORMAT_RGBA8)
	noise_tex = PixelArt.build_noise(128, world_seed)
	_bake_all()
	albedo_tex = ImageTexture.create_from_image(albedo_img)
	data_tex = ImageTexture.create_from_image(data_img)

	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(_sprite)
	_sprite.texture = albedo_tex

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_mat.set_shader_parameter("data_tex", data_tex)
	_mat.set_shader_parameter("noise_tex", noise_tex)
	_mat.set_shader_parameter("world_size", Vector2(w.w, w.h))
	_sprite.material = _mat

func _bake_all() -> void:
	var n := world.w * world.h
	for i in n:
		var x := i % world.w
		var y := int(i / world.w)
		albedo_img.set_pixel(x, y, world.cell_color(i))
		data_img.set_pixel(x, y, world.cell_data(i))
	world.dirty_cells.resize(0)
	world.full_redraw = false
	_needs_upload = true

## Re-bakes only the cells the simulation touched.
func flush_dirty() -> void:
	if world == null:
		return
	if world.full_redraw:
		_bake_all()
		return
	var dc := world.dirty_cells
	if dc.is_empty():
		return
	for k in dc.size():
		var i: int = dc[k]
		var x := i % world.w
		var y := int(i / world.w)
		albedo_img.set_pixel(x, y, world.cell_color(i))
		data_img.set_pixel(x, y, world.cell_data(i))
	world.dirty_cells.resize(0)
	_needs_upload = true

func _process(delta: float) -> void:
	_time += delta
	_cloud_scroll += delta
	if _mat != null:
		_mat.set_shader_parameter("time_s", _time)
		_mat.set_shader_parameter("cloud_scroll", _cloud_scroll)
	flush_dirty()
	if _needs_upload:
		albedo_tex.update(albedo_img)
		data_tex.update(data_img)
		_needs_upload = false

# --------------------------------------------------------------------------
# Ambient parameters driven by the climate / weather systems
# --------------------------------------------------------------------------
func set_ambient(tint: Color, day_factor: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("ambient_tint", Vector3(tint.r, tint.g, tint.b))
	_mat.set_shader_parameter("day_factor", day_factor)

func set_weather(rain: float, wind: Vector2, cloud_amount: float, heat: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("rain", rain)
	_mat.set_shader_parameter("wind", wind)
	_mat.set_shader_parameter("cloud_amount", cloud_amount)
	_mat.set_shader_parameter("heat", heat)
