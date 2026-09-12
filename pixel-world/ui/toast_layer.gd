extends Control
## Transient notifications for world events. Stacked, fading, non-interactive.

const LIFETIME: float = 5.0
const MAX_SHOWN: int = 4

var _items: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.toast.connect(_on_toast)

func _on_toast(text: String, color: Color) -> void:
	_items.append({"text": text, "color": color, "t": 0.0})
	if _items.size() > MAX_SHOWN:
		_items.remove_at(0)

func _process(delta: float) -> void:
	if _items.is_empty():
		return
	var i := 0
	while i < _items.size():
		_items[i]["t"] = float(_items[i]["t"]) + delta
		if float(_items[i]["t"]) > LIFETIME:
			_items.remove_at(i)
		else:
			i += 1
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var w: float = size.x
	var y := 0.0
	for item in _items:
		var t: float = item["t"]
		var fade: float = clampf(minf(t * 4.0, (LIFETIME - t) * 1.4), 0.0, 1.0)
		var slide: float = (1.0 - clampf(t * 5.0, 0.0, 1.0)) * 14.0
		var text: String = item["text"]
		var col: Color = item["color"]
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		var bw: float = minf(w, ts.x + 20.0)
		var r := Rect2((w - bw) * 0.5, y + slide, bw, 22.0)
		draw_rect(r, Color(0.04, 0.05, 0.08, 0.78 * fade), true)
		draw_rect(r, Color(col.r, col.g, col.b, 0.35 * fade), false, 1.0)
		draw_string(font, Vector2(r.position.x + 10.0, r.position.y + 15.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, bw - 20.0, 11,
				Color(col.r, col.g, col.b, fade))
		y += 26.0
