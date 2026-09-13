extends PanelContainer
## Top status strip: the four numbers that matter, plus a dim context line.

var _year: Label
var _pop: Label
var _species: Label
var _temp: Label
var _context: Label

func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel(12, UITheme.BG))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 1)
	add_child(root)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	root.add_child(row)
	_year = _stat(row, "YEAR", "0")
	_pop = _stat(row, "POPULATION", "0")
	_species = _stat(row, "SPECIES", "0")
	_temp = _stat(row, "TEMPERATURE", "0°C")

	_context = UITheme.label("", 10, UITheme.TEXT_DIM)
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_context)

func _stat(parent: Node, caption: String, value: String) -> Label:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", -1)
	parent.add_child(box)
	var cap := UITheme.label(caption, 9, UITheme.TEXT_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	var val := UITheme.label(value, 17, UITheme.TEXT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(val)
	return val

func refresh(sim: Simulation) -> void:
	_year.text = HudFormat.commas(sim.climate.year)
	_pop.text = HudFormat.commas(sim.population())
	_species.text = str(sim.species_count())
	_temp.text = "%d°C" % int(round(sim.stats.avg_temperature))
	var ev := ""
	if sim.weather.event_id != WeatherSystem.E.NONE:
		ev = "  ·  %s" % WeatherSystem.E_NAMES[sim.weather.event_id]
	_context.text = "%s  ·  day %d  ·  %s  ·  seed %d  ·  %s%s" % [
		sim.climate.time_label(), sim.climate.day,
		WeatherSystem.W_NAMES[sim.weather.weather], sim.world_seed,
		WorldGen.ARCHETYPE_NAMES[sim.world.archetype], ev]
	_temp.add_theme_color_override("font_color",
			UITheme.BAD if sim.stats.avg_temperature > 32.0
			else (UITheme.ACCENT if sim.stats.avg_temperature < 2.0 else UITheme.TEXT))
