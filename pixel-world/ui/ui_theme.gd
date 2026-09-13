class_name UITheme
extends RefCounted
## Shared look-and-feel. Everything is built in code, so this is where the
## visual language of the interface actually lives: dark translucent glass,
## thin light borders, a restrained accent palette, and type sized for a phone.

const BG := Color(0.055, 0.065, 0.095, 0.80)
const BG_SOLID := Color(0.055, 0.065, 0.095, 0.95)
const BG_RAISED := Color(0.105, 0.125, 0.170, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.10)
const BORDER_HI := Color(1.0, 1.0, 1.0, 0.30)
const TEXT := Color(0.90, 0.93, 0.97, 1.0)
const TEXT_DIM := Color(0.62, 0.68, 0.78, 1.0)
const ACCENT := Color(0.45, 0.85, 0.95, 1.0)
const WARN := Color(1.0, 0.62, 0.30, 1.0)
const GOOD := Color(0.45, 0.90, 0.55, 1.0)
const BAD := Color(1.0, 0.42, 0.42, 1.0)

## Accent colour per tool, used to tint icons and the active highlight.
const TOOL_COLORS: PackedColorArray = [
	Color(0.80, 0.88, 0.96),   # INSPECT
	Color(0.52, 0.76, 1.00),   # RAIN
	Color(1.00, 0.52, 0.22),   # FIRE
	Color(0.36, 0.72, 1.00),   # WATER
	Color(0.52, 0.92, 0.44),   # PLANT
	Color(0.72, 0.70, 0.74),   # ROCK
	Color(1.00, 0.78, 0.38),   # METEOR
	Color(1.00, 0.40, 0.28),   # VOLCANO
	Color(0.70, 0.92, 1.00),   # ICE
	Color(0.82, 0.90, 0.86),   # WIND
	Color(0.92, 0.68, 0.98),   # CREATURE
]

static func panel(radius: int = 10, bg: Color = BG, border: Color = BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb

static func make_panel(radius: int = 10, bg: Color = BG) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel(radius, bg))
	return p

static func label(text: String, size: int = 13, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	return l

## Small pill button used for speed and window controls.
static func text_button(text: String, size: int = 13, min_w: float = 40.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 32.0)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", TEXT_DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_stylebox_override("normal", panel(8, Color(0.10, 0.12, 0.17, 0.78)))
	b.add_theme_stylebox_override("hover", panel(8, Color(0.16, 0.19, 0.26, 0.85)))
	b.add_theme_stylebox_override("pressed", panel(8, Color(0.20, 0.26, 0.34, 0.9), BORDER_HI))
	return b

static func set_button_active(b: Button, active: bool, accent: Color = ACCENT) -> void:
	if active:
		b.add_theme_stylebox_override("normal",
				panel(8, Color(accent.r * 0.30, accent.g * 0.30, accent.b * 0.34, 0.92), accent))
		b.add_theme_color_override("font_color", accent)
	else:
		b.add_theme_stylebox_override("normal", panel(8, Color(0.10, 0.12, 0.17, 0.78)))
		b.add_theme_color_override("font_color", TEXT_DIM)

## Draws a labelled horizontal bar (used by the creature card for genes).
static func draw_gene_bar(ci: CanvasItem, rect: Rect2, value: float, color: Color) -> void:
	ci.draw_rect(rect, Color(1, 1, 1, 0.08), true)
	var fg := rect
	fg.size.x = rect.size.x * clampf(value, 0.0, 1.0)
	ci.draw_rect(fg, color, true)
	ci.draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)

## Draws a filled sparkline for a history series.
static func draw_series(ci: CanvasItem, rect: Rect2, data: PackedFloat32Array,
		color: Color, fill: bool = true) -> void:
	if data.size() < 2:
		return
	var lo: float = data[0]
	var hi: float = data[0]
	for v in data:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span: float = maxf(0.0001, hi - lo)
	var pts := PackedVector2Array()
	var n := data.size()
	for i in n:
		var x := rect.position.x + rect.size.x * float(i) / float(n - 1)
		var y := rect.position.y + rect.size.y * (1.0 - (data[i] - lo) / span)
		pts.append(Vector2(x, y))
	if fill:
		var poly := pts.duplicate()
		poly.append(Vector2(rect.end.x, rect.end.y))
		poly.append(Vector2(rect.position.x, rect.end.y))
		ci.draw_colored_polygon(poly, Color(color.r, color.g, color.b, 0.18))
	ci.draw_polyline(pts, color, 1.4, true)
