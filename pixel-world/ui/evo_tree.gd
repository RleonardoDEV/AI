extends PanelContainer
## The evolutionary tree: every species drawn under the ancestor it diverged
## from, with the generation it appeared at, its peak and current population,
## and whether the line is extinct.
##
## This is the pay-off screen for the genetics system — it is the only place
## the whole history of the run is visible at once.

const ROW_H: float = 19.0
const INDENT: float = 16.0

var sim: Simulation
var _canvas: Control
var _scroll: ScrollContainer
var _rows: Array[Dictionary] = []
var _t: float = 99.0

func setup(simulation: Simulation) -> void:
	sim = simulation
	add_theme_stylebox_override("panel", UITheme.panel(14, UITheme.BG_SOLID))
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	head.add_child(UITheme.label("EVOLUTIONARY TREE", 15, UITheme.TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UITheme.text_button("×", 15, 28.0)
	close.pressed.connect(func(): visible = false)
	head.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_tree)
	_scroll.add_child(_canvas)

func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	_t += delta
	if _t < 0.6:
		return
	_t = 0.0
	_rebuild()

## Depth-first walk from the founding stock, so descendants sit under parents.
func _rebuild() -> void:
	_rows.clear()
	var children := {}
	for s in sim.registry.species:
		if s.parent_id >= 0:
			if not children.has(s.parent_id):
				children[s.parent_id] = []
			children[s.parent_id].append(s.id)
	var roots: Array[int] = []
	for s in sim.registry.species:
		if s.parent_id < 0:
			roots.append(s.id)
	for r in roots:
		_walk(r, 0, children)
	_canvas.custom_minimum_size = Vector2(0, maxf(40.0, float(_rows.size()) * ROW_H + 8.0))
	_canvas.queue_redraw()

func _walk(id: int, depth: int, children: Dictionary) -> void:
	var sp: Species = sim.registry.get_species(id)
	if sp == null or depth > 24:
		return
	# Lines that died out without descendants are hidden once the tree grows,
	# otherwise short-lived mutants bury the interesting branches.
	var kids: Array = children.get(id, [])
	var interesting: bool = sp.population > 0 or sp.peak_population >= 3 or not kids.is_empty()
	if interesting:
		_rows.append({"sp": sp, "depth": depth, "row": _rows.size()})
	for k in kids:
		_walk(k, depth + (1 if interesting else 0), children)

func _draw_tree() -> void:
	var font := ThemeDB.fallback_font
	var w: float = _canvas.size.x
	if _rows.is_empty():
		_canvas.draw_string(font, Vector2(4, 18), "No lineages yet.",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UITheme.TEXT_DIM)
		return
	# Remember each species' row so child connectors can be drawn.
	var row_of := {}
	for r in _rows:
		row_of[(r["sp"] as Species).id] = r
	for r in _rows:
		var sp: Species = r["sp"]
		var depth: int = r["depth"]
		var y: float = float(r["row"]) * ROW_H + 12.0
		var x: float = 6.0 + float(depth) * INDENT

		# Connector from the parent row.
		if sp.parent_id >= 0 and row_of.has(sp.parent_id):
			var pr: Dictionary = row_of[sp.parent_id]
			var py: float = float(pr["row"]) * ROW_H + 12.0
			var px: float = 6.0 + float(pr["depth"]) * INDENT + 4.0
			var line := Color(1, 1, 1, 0.18)
			_canvas.draw_line(Vector2(px, py + 4.0), Vector2(px, y), line, 1.0)
			_canvas.draw_line(Vector2(px, y), Vector2(x - 2.0, y), line, 1.0)

		var col: Color = sp.color
		if sp.extinct:
			col = Color(col.r * 0.45 + 0.10, col.g * 0.45 + 0.10, col.b * 0.45 + 0.12, 1.0)
		_canvas.draw_rect(Rect2(x, y - 3.5, 7.0, 7.0), col, true)
		var text := sp.full_name()
		_canvas.draw_string(font, Vector2(x + 12.0, y + 4.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				UITheme.TEXT if not sp.extinct else UITheme.TEXT_DIM)
		var right := ""
		if sp.extinct:
			right = "extinct y%d · peak %d" % [sp.extinct_year, sp.peak_population]
		else:
			right = "pop %d · peak %d" % [sp.population, sp.peak_population]
		_canvas.draw_string(font, Vector2(w - 190.0, y + 4.0),
				"%s · gen %d · y%d" % [sp.diet_label().substr(0, 4), sp.founder_generation,
				sp.founded_year], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
		_canvas.draw_string(font, Vector2(w - 92.0, y + 4.0), right,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
