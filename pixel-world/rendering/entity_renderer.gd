class_name EntityRenderer
extends Node2D
## Draws every creature and corpse in one custom-draw pass.
##
## All species share a single atlas texture, so the whole population batches
## into very few draw calls. Only what intersects the (expanded) view is
## considered, and detail passes — specular glint, shadow, selection ring —
## switch on progressively with zoom, so a zoomed-out ecosystem costs far less
## per creature than a zoomed-in one.

## Detail passes switch on with zoom: each one is an extra draw call per
## creature, and at low zoom none of them are visible anyway.
const SHADOW_ZOOM: float = 5.0
const DETAIL_ZOOM: float = 9.0
const BAR_ZOOM: float = 11.0

var sim: Simulation
var bank: SpriteBank
var glow_tex: Texture2D
var selected: Creature = null

var _view: Rect2 = Rect2()
var _zoom: float = 4.0
var _time: float = 0.0
var drawn_count: int = 0

func setup(simulation: Simulation, sprite_bank: SpriteBank) -> void:
	sim = simulation
	bank = sprite_bank
	glow_tex = PixelArt.build_glow(32, 1.6)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_view(view: Rect2, zoom: float) -> void:
	_view = view
	_zoom = zoom

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	if sim == null or bank == null:
		return
	var mgr := sim.entities
	var atlas := bank.atlas_tex
	var detail := bank.detail_tex
	var view := _view.grow(6.0)
	var show_shadow: bool = _zoom >= SHADOW_ZOOM
	var show_detail: bool = _zoom >= DETAIL_ZOOM
	var texels: float = GameConfig.SPRITE_TEXELS_PER_CELL
	drawn_count = 0

	# --- Carrion first, so living animals draw over it --------------------
	var corpses := mgr.live_corpses()
	for k in corpses.size():
		var ci: int = corpses[k]
		var cp: Vector2 = mgr.corpse_pos[ci]
		if not view.has_point(cp):
			continue
		var fade: float = mgr.corpse_fade(ci)
		var col: Color = mgr.corpse_color[ci]
		draw_rect(Rect2(cp - Vector2(0.9, 0.6), Vector2(1.8, 1.2)),
				Color(col.r, col.g, col.b, 0.55 * fade), true)

	# --- Creatures --------------------------------------------------------
	# Drawn in separate passes (shadows, then bodies, then details) rather than
	# per-creature. Godot batches consecutive draws that share a texture, so
	# interleaving three textures per creature turned every animal into three
	# draw calls; grouping by texture collapses the whole population into a
	# handful. This alone cut ~1400 draw calls to ~10.
	var ids := mgr.alive_ids
	var n := ids.size()
	var texel_span: float = float(PixelArt.TILE) / texels

	if show_shadow:
		for k in n:
			var c: Creature = mgr.creatures[ids[k]]
			if not c.alive or not view.has_point(c.pos):
				continue
			var span := texel_span * c.draw_scale()
			var sh := span * 0.72
			draw_texture_rect(glow_tex,
					Rect2(c.pos - Vector2(sh, sh) * 0.5 + Vector2(0.0, span * 0.22),
							Vector2(sh, sh)),
					false, Color(0.02, 0.02, 0.05, 0.30))

	for k in n:
		var c: Creature = mgr.creatures[ids[k]]
		if not c.alive or not view.has_point(c.pos):
			continue
		drawn_count += 1
		var span := texel_span * c.draw_scale()
		var half := span * 0.5
		# Gait bob, applied before snapping so it lands as a whole-texel hop.
		var bob: float = sin(c.anim_t * PI) * span * 0.055
		# Snap to whole world texels: the terrain is pixel-aligned, and
		# unsnapped sprites shimmer against it when the camera moves.
		var origin := Vector2(floor(c.pos.x - half), floor(c.pos.y - half + bob))
		var frame: int = int(c.anim_t) & 1
		# Hurt animals flash toward red.
		var tint := c.color
		if c.health < 0.45:
			tint = tint.lerp(Color(1.0, 0.45, 0.4), (0.45 - c.health) * 0.9)
		draw_texture_rect_region(atlas, Rect2(origin, Vector2(span, span)),
				bank.region(c.sprite_slot, c.facing, frame), tint)

	if show_detail:
		for k in n:
			var c: Creature = mgr.creatures[ids[k]]
			if not c.alive or not view.has_point(c.pos):
				continue
			var span := texel_span * c.draw_scale()
			var half := span * 0.5
			var bob: float = sin(c.anim_t * PI) * span * 0.055
			var origin := Vector2(floor(c.pos.x - half), floor(c.pos.y - half + bob))
			var frame: int = int(c.anim_t) & 1
			draw_texture_rect_region(detail, Rect2(origin, Vector2(span, span)),
					bank.region(c.sprite_slot, c.facing, frame), Color(1, 1, 1, 0.5))

	# --- Selection and health, only for the few creatures that need it ----
	if selected != null and selected.alive and view.has_point(selected.pos):
		var span := texel_span * selected.draw_scale()
		var pulse: float = 0.6 + 0.4 * sin(_time * 5.0)
		draw_arc(selected.pos, span * 0.85, 0.0, TAU, 20,
				Color(1.0, 1.0, 0.95, 0.85 * pulse), 0.22, false)
		_draw_bar(selected.pos + Vector2(0.0, -span * 0.62), span * 0.9,
				selected.health, UITheme.GOOD)
	if _zoom >= BAR_ZOOM:
		for k in n:
			var c: Creature = mgr.creatures[ids[k]]
			if not c.alive or c.health >= 0.7 or c == selected:
				continue
			if not view.has_point(c.pos):
				continue
			var span := texel_span * c.draw_scale()
			_draw_bar(c.pos + Vector2(0.0, -span * 0.62), span * 0.8, c.health,
					Color(0.85, 0.35, 0.35))

func _draw_bar(at: Vector2, width: float, value: float, color: Color) -> void:
	var h: float = maxf(0.22, width * 0.10)
	var bg := Rect2(at - Vector2(width * 0.5, h * 0.5), Vector2(width, h))
	draw_rect(bg, Color(0.05, 0.05, 0.08, 0.65), true)
	var fg := bg
	fg.size.x = width * clampf(value, 0.0, 1.0)
	draw_rect(fg, color, true)

## Nearest creature to a world position within `radius`, or null.
func pick(at: Vector2, radius: float) -> Creature:
	if sim == null:
		return null
	var mgr := sim.entities
	var ids: PackedInt32Array = mgr.grid.query(at.x, at.y, radius)
	var best: Creature = null
	var best_d := radius * radius
	for k in ids.size():
		var c: Creature = mgr.creatures[ids[k]]
		if not c.alive:
			continue
		var d := c.pos.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = c
	return best
