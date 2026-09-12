class_name SkyOverlay
extends CanvasLayer
## Screen-space atmosphere: a multiplied vignette/night pass and an additive
## weather pass. Two full-screen quads, no per-drop geometry.

var tint_rect: ColorRect
var glow_rect: ColorRect
var _tint_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _time: float = 0.0
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE

func _ready() -> void:
	layer = 2
	# Blend modes are declared in the shaders themselves (blend_mul /
	# blend_add): a CanvasItem can only carry one material, and that slot is
	# taken by the shader.
	tint_rect = _make_rect("res://rendering/shaders/sky_tint.gdshader")
	_tint_mat = tint_rect.material
	glow_rect = _make_rect("res://rendering/shaders/sky_glow.gdshader")
	_glow_mat = glow_rect.material
	EventBus.screen_flash.connect(_on_flash)

func _make_rect(shader_path: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	r.material = mat
	add_child(r)
	return r

func _on_flash(color: Color, strength: float) -> void:
	_flash = maxf(_flash, strength)
	_flash_color = color

func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta * 2.6)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("time_s", _time)
		_glow_mat.set_shader_parameter("flash", _flash)
		_glow_mat.set_shader_parameter("flash_color",
				Vector3(_flash_color.r, _flash_color.g, _flash_color.b))
		var vp := get_viewport().get_visible_rect().size
		_glow_mat.set_shader_parameter("aspect", vp.x / maxf(1.0, vp.y))

func set_weather(rain: float, snow: float, wind: Vector2, night: float,
		golden: float, storm: float) -> void:
	if _glow_mat != null:
		_glow_mat.set_shader_parameter("rain", rain)
		_glow_mat.set_shader_parameter("snow", snow)
		_glow_mat.set_shader_parameter("wind", wind)
		_glow_mat.set_shader_parameter("golden", golden)
	if _tint_mat != null:
		_tint_mat.set_shader_parameter("night", night)
		_tint_mat.set_shader_parameter("storm", storm)
