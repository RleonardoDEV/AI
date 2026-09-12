extends PanelContainer
## Full statistics overlay: live census, history graphs, mortality breakdown
## and the species leaderboard.

var sim: Simulation
var _body: VBoxContainer
var _summary: Label
var _graphs: Control
var _causes: Control
var _species_list: VBoxContainer
var _t: float = 99.0

func setup(simulation: Simulation) -> void:
	sim = simulation
	add_theme_stylebox_override("panel", UITheme.panel(14, UITheme.BG_SOLID))
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)

	var head := HBoxContainer.new()
	_body.add_child(head)
	head.add_child(UITheme.label("STATISTICS", 15, UITheme.TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UITheme.text_button("×", 15, 28.0)
	close.pressed.connect(func(): visible = false)
	head.add_child(close)

	_summary = UITheme.label("", 11, UITheme.TEXT)
	_body.add_child(_summary)

	_body.add_child(UITheme.label("HISTORY", 9, UITheme.TEXT_DIM))
	_graphs = Control.new()
	_graphs.custom_minimum_size = Vector2(0, 200)
	_graphs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graphs.draw.connect(_draw_graphs)
	_body.add_child(_graphs)

	_body.add_child(UITheme.label("MORTALITY", 9, UITheme.TEXT_DIM))
	_causes = Control.new()
	_causes.custom_minimum_size = Vector2(0, 108)
	_causes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_causes.draw.connect(_draw_causes)
	_body.add_child(_causes)

	_body.add_child(UITheme.label("SPECIES", 9, UITheme.TEXT_DIM))
	_species_list = VBoxContainer.new()
	_species_list.add_theme_constant_override("separation", 0)
	_body.add_child(_species_list)

func _process(delta: float) -> void:
	if not visible or sim == null:
		return
	_t += delta
	if _t < 0.4:
		return
	_t = 0.0
	_refresh()

func _refresh() -> void:
	var st := sim.stats
	var dom := sim.registry.dominant()
	var dom_name := dom.full_name() if dom != null else "—"
	var days: float = float(sim.climate.day) + sim.climate.day_phase
	_summary.text = ("population %s   species %d alive / %d ever\n"
		+ "births %s   deaths %s   attacks %s   mutations %s\n"
		+ "generation avg %.2f   max %d\n"
		+ "dominant %s (%d)\n"
		+ "temperature %.1f°C   vegetation %.0f%%   flora %d   carrion %d\n"
		+ "elapsed %.1f days / %d years   peak population %d\n"
		+ "extinctions %d   world events %d") % [
		HudFormat.commas(sim.population()), sim.species_count(),
		sim.registry.total_species_created,
		HudFormat.commas(st.births), HudFormat.commas(st.deaths),
		HudFormat.commas(st.attacks), HudFormat.commas(st.mutations),
		st.avg_generation, st.max_generation,
		dom_name, dom.population if dom != null else 0,
		st.avg_temperature, st.total_vegetation * 100.0, sim.flora.count,
		sim.entities.corpse_count,
		days, sim.climate.year, st.peak_population,
		sim.registry.total_extinctions, sim.weather.events_fired]
	_graphs.queue_redraw()
	_causes.queue_redraw()

	for c in _species_list.get_children():
		c.queue_free()
	var living := sim.registry.living()
	living.sort_custom(func(a, b): return a.population > b.population)
	for k in mini(10, living.size()):
		var s: Species = living[k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = s.color
		row.add_child(dot)
		row.add_child(UITheme.label(s.full_name(), 10, UITheme.TEXT))
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp2)
		row.add_child(UITheme.label("%s · gen %d · %d" % [
				s.diet_label().substr(0, 4), s.founder_generation, s.population],
				10, UITheme.TEXT_DIM))
		_species_list.add_child(row)

func _draw_graphs() -> void:
	var st := sim.stats
	var w: float = _graphs.size.x
	var series := [
		["Population", st.hist_population, UITheme.ACCENT],
		["Species", st.hist_species, Color(0.75, 0.95, 0.55)],
		["Temperature °C", st.hist_temp, UITheme.WARN],
		["Vegetation", st.hist_veg, UITheme.GOOD],
	]
	var font := ThemeDB.fallback_font
	var y := 0.0
	var row_h := 46.0
	for s in series:
		var label: String = s[0]
		var data: PackedFloat32Array = s[1]
		var col: Color = s[2]
		var r := Rect2(0, y + 10, w, row_h - 14)
		_graphs.draw_rect(r, Color(1, 1, 1, 0.035), true)
		UITheme.draw_series(_graphs, r, data, col)
		var last := "—"
		if data.size() > 0:
			last = "%.2f" % data[data.size() - 1]
		_graphs.draw_string(font, Vector2(2, y + 8), label, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 8, UITheme.TEXT_DIM)
		_graphs.draw_string(font, Vector2(w - 52, y + 8), last, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 8, col)
		y += row_h

func _draw_causes() -> void:
	var st := sim.stats
	var total := 0
	for v in st.deaths_by_cause:
		total += v
	total = maxi(1, total)
	var font := ThemeDB.fallback_font
	var w: float = _causes.size.x
	var y := 0.0
	for i in st.deaths_by_cause.size():
		var n: int = st.deaths_by_cause[i]
		var frac := float(n) / float(total)
		_causes.draw_string(font, Vector2(0, y + 8), Creature.CAUSE_NAMES[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.TEXT_DIM)
		UITheme.draw_gene_bar(_causes, Rect2(74, y + 2, w - 118, 7), frac,
				Color.from_hsv(0.02 + float(i) * 0.07, 0.6, 0.95))
		_causes.draw_string(font, Vector2(w - 40, y + 8), str(n),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UITheme.TEXT_DIM)
		y += 11.0
