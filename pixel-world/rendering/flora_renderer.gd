class_name FloraRenderer
extends Node2D
## Trees and shrubs, drawn from the flora pool with a per-plant wind sway.
##
## The sway is the cheapest "world is alive" signal there is: a horizontal
## offset driven by a phase unique to each plant, scaled by the live wind
## vector, so a gust visibly travels across a forest.

var flora: FloraSystem
var tree_tex: ImageTexture
var shrub_tex: ImageTexture
var glow_tex: Texture2D

var _view: Rect2 = Rect2()
var _zoom: float = 4.0
var _time: float = 0.0
var _wind: Vector2 = Vector2.ZERO
var drawn_count: int = 0

func setup(f: FloraSystem) -> void:
	flora = f
	tree_tex = ImageTexture.create_from_image(PixelArt.build_flora_atlas())
	shrub_tex = ImageTexture.create_from_image(PixelArt.build_shrub_atlas())
	glow_tex = PixelArt.build_glow(32, 1.6)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_view(view: Rect2, zoom: float, wind: Vector2) -> void:
	_view = view
	_zoom = zoom
	_wind = wind

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	if flora == null:
		return
	var view := _view.grow(8.0)
	var texels: float = GameConfig.SPRITE_TEXELS_PER_CELL
	var wind_x: float = _wind.x
	var wind_mag: float = _wind.length()
	var show_shadow: bool = _zoom >= 5.0
	drawn_count = 0

	# Two texture-grouped passes (shadows, then plants) so the whole forest
	# batches instead of costing two draw calls per plant.
	if show_shadow:
		for i in flora.capacity:
			if flora.active[i] == 0:
				continue
			var p: Vector2 = flora.pos[i]
			if not view.has_point(p):
				continue
			var is_tree_s: bool = flora.kind[i] == 0
			if not is_tree_s:
				continue
			var stage_s: int = flora.stage[i]
			var span_s: float = float(PixelArt.TREE_TILE) / texels \
					* (0.55 + 0.45 * (float(stage_s) / float(PixelArt.TREE_STAGES - 1)))
			var sway_s: float = sin(_time * 1.35 + flora.phase[i]) * (0.12 + wind_mag * 0.55) \
					+ wind_x * 0.45
			draw_texture_rect(glow_tex,
					Rect2(p - Vector2(span_s, span_s) * 0.34
							+ Vector2(sway_s * 0.2, span_s * 0.22),
							Vector2(span_s, span_s) * 0.68),
					false, Color(0.02, 0.03, 0.05, 0.28))

	for i in flora.capacity:
		if flora.active[i] == 0:
			continue
		var p: Vector2 = flora.pos[i]
		if not view.has_point(p):
			continue
		drawn_count += 1
		var stage: int = flora.stage[i]
		# Wind sway: the cheapest "this world is alive" signal there is. A
		# per-plant phase means a gust visibly travels across a forest.
		var sway: float = sin(_time * 1.35 + flora.phase[i]) * (0.12 + wind_mag * 0.55) \
				+ wind_x * 0.45
		if flora.kind[i] == 0:
			var span: float = float(PixelArt.TREE_TILE) / texels \
					* (0.55 + 0.45 * (float(stage) / float(PixelArt.TREE_STAGES - 1)))
			var origin := Vector2(p.x - span * 0.5 + sway * 0.5, p.y - span * 0.55)
			var src := Rect2(float(stage * PixelArt.TREE_TILE),
					float(int(flora.variant[i]) % PixelArt.TREE_VARIANTS * PixelArt.TREE_TILE),
					float(PixelArt.TREE_TILE), float(PixelArt.TREE_TILE))
			draw_texture_rect_region(tree_tex, Rect2(origin, Vector2(span, span)), src)
		else:
			var span2: float = float(PixelArt.BUSH_TILE) / texels * 1.15
			var origin2 := Vector2(p.x - span2 * 0.5 + sway * 0.3, p.y - span2 * 0.5)
			var src2 := Rect2(float(int(flora.variant[i]) % 8 * PixelArt.BUSH_TILE), 0.0,
					float(PixelArt.BUSH_TILE), float(PixelArt.BUSH_TILE))
			draw_texture_rect_region(shrub_tex, Rect2(origin2, Vector2(span2, span2)), src2)
