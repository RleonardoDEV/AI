extends PanelContainer
## Inspector for a tapped creature: vitals, behaviour and its genome plotted
## against its species average, so you can see *how* an individual differs
## from its lineage rather than just reading numbers.

var creature: Creature = null
var _name: Label
var _sub: Label
var _facts: Label
var _bars: Control
var _dna: Control
var _swatch: ColorRect

func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel(12, UITheme.BG_SOLID))
	custom_minimum_size = Vector2(268, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 3)
	add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	root.add_child(head)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(14, 14)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_swatch)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	head.add_child(titles)
	_name = UITheme.label("—", 14, UITheme.TEXT)
	titles.add_child(_name)
	_sub = UITheme.label("", 9, UITheme.TEXT_DIM)
	titles.add_child(_sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := UITheme.text_button("×", 15, 26.0)
	close.pressed.connect(func(): EventBus.creature_deselected.emit())
	head.add_child(close)

	_facts = UITheme.label("", 10, UITheme.TEXT_DIM)
	root.add_child(_facts)

	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(248, 46)
	_bars.draw.connect(_draw_bars)
	root.add_child(_bars)

	root.add_child(UITheme.label("DNA", 9, UITheme.TEXT_DIM))
	_dna = Control.new()
	_dna.custom_minimum_size = Vector2(248, 54)
	_dna.draw.connect(_draw_dna)
	root.add_child(_dna)

func show_creature(c: Creature) -> void:
	creature = c
	visible = c != null
	if c == null:
		return
	_swatch.color = c.color
	_name.text = c.species.full_name() if c.species != null else "Unknown"
	_sub.text = "%s · gen %d · %s" % [
		c.species.diet_label() if c.species != null else DNA.diet_label(c.diet),
		c.generation, c.state_name()]

func _process(_delta: float) -> void:
	if creature == null or not visible:
		return
	if not creature.alive:
		EventBus.creature_deselected.emit()
		return
	_sub.text = "%s · gen %d · %s" % [
		DNA.diet_label(creature.diet), creature.generation, creature.state_name()]
	_facts.text = "age %s   speed %.1f   vision %.0f   size %.2f\ndrive %.0f%%   stamina %.2f   aquatic %.2f   fear %.2f" % [
		creature.age_label(), creature.max_speed, creature.vision, creature.body_size,
		creature.repro_drive * 100.0, creature.stamina, creature.aquatic, creature.fear_gene]
	_bars.queue_redraw()
	_dna.queue_redraw()

func _draw_bars() -> void:
	if creature == null:
		return
	var w: float = _bars.size.x
	var rows := [
		["Health", creature.health, UITheme.GOOD],
		["Energy", creature.energy, UITheme.ACCENT],
		["Hunger", creature.hunger, UITheme.WARN],
		["Thirst", creature.thirst, Color(0.45, 0.72, 1.0)],
	]
	var y := 0.0
	for r in rows:
		var label: String = r[0]
		var v: float = r[1]
		var col: Color = r[2]
		var font := ThemeDB.fallback_font
		_bars.draw_string(font, Vector2(0, y + 8), label, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 9, UITheme.TEXT_DIM)
		UITheme.draw_gene_bar(_bars, Rect2(44, y + 2, w - 82, 7), v, col)
		_bars.draw_string(font, Vector2(w - 32, y + 8), "%d%%" % int(v * 100.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UITheme.TEXT_DIM)
		y += 11.0

## Each gene as a vertical bar; the species average is marked with a tick, so
## an individual's deviation from its lineage is visible at a glance.
func _draw_dna() -> void:
	if creature == null:
		return
	var n := DNA.NUM_GENES
	var w: float = _dna.size.x
	var h: float = _dna.size.y - 12.0
	var bw: float = w / float(n)
	var centroid: PackedFloat32Array = creature.species.centroid if creature.species != null else creature.dna
	var font := ThemeDB.fallback_font
	for i in n:
		var x := float(i) * bw
		var v := DNA.norm(creature.dna, i)
		var cv := DNA.norm(centroid, i)
		var col := Color(0.45, 0.85, 0.95)
		if v > cv + 0.12:
			col = UITheme.GOOD
		elif v < cv - 0.12:
			col = UITheme.WARN
		_dna.draw_rect(Rect2(x + 1.0, 0.0, bw - 2.0, h), Color(1, 1, 1, 0.07), true)
		_dna.draw_rect(Rect2(x + 1.0, h * (1.0 - v), bw - 2.0, h * v), col, true)
		# Species-average tick.
		_dna.draw_line(Vector2(x + 0.5, h * (1.0 - cv)), Vector2(x + bw - 0.5, h * (1.0 - cv)),
				Color(1, 1, 1, 0.72), 1.0)
		_dna.draw_string(font, Vector2(x + 1.0, h + 9.0), DNA.NAMES[i].substr(0, 2),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 7, UITheme.TEXT_DIM)
