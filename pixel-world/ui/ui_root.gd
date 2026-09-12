extends CanvasLayer
## Builds and owns the whole interface.
##
## Layout philosophy: the world fills the screen. The interface is a thin
## status strip at the top, a compact minimap and a few icon buttons on the
## right, and the tool palette plus time controls docked at the bottom.
## Everything else (statistics, evolutionary tree, creature inspector) appears
## only on demand and can be dismissed with one tap.

var main: Node
var sim: Simulation

var hud: PanelContainer
var toolbar: PanelContainer
var speedbar: PanelContainer
var minimap: PanelContainer
var card: PanelContainer
var stats: PanelContainer
var tree_panel: PanelContainer
var debug: PanelContainer
var toasts: Control
var menu: PanelContainer

var _side_buttons: Dictionary = {}
var _hud_timer: float = 0.0

func setup(main_node: Node) -> void:
	main = main_node
	sim = main.sim
	layer = 5

	# --- Top status strip -------------------------------------------------
	hud = load("res://ui/hud_bar.gd").new()
	var hud_margin := MarginContainer.new()
	hud_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_pad(hud_margin, 8, 8, 8, 0)
	hud_margin.add_child(hud)
	add_child(hud_margin)

	# --- Toasts under the strip -------------------------------------------
	toasts = load("res://ui/toast_layer.gd").new()
	toasts.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toasts.offset_top = 78
	toasts.offset_left = 12
	toasts.offset_right = -12
	toasts.custom_minimum_size = Vector2(0, 120)
	add_child(toasts)

	# --- Right rail: minimap + panel toggles ------------------------------
	var rail := VBoxContainer.new()
	rail.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rail.offset_top = 80
	rail.offset_right = -8
	rail.offset_left = -148
	rail.alignment = BoxContainer.ALIGNMENT_BEGIN
	rail.add_theme_constant_override("separation", 6)
	add_child(rail)

	minimap = load("res://ui/minimap.gd").new()
	minimap.setup(sim, main.terrain)
	minimap.visible = Config.show_minimap
	rail.add_child(minimap)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 4)
	rail.add_child(btns)
	_side_buttons["stats"] = _rail_button(btns, "STATS", func(): _toggle(stats))
	_side_buttons["tree"] = _rail_button(btns, "TREE", func(): _toggle(tree_panel))
	var btns2 := HBoxContainer.new()
	btns2.alignment = BoxContainer.ALIGNMENT_END
	btns2.add_theme_constant_override("separation", 4)
	rail.add_child(btns2)
	_side_buttons["map"] = _rail_button(btns2, "MAP", func():
		minimap.visible = not minimap.visible
		Config.show_minimap = minimap.visible
		Config.save_settings())
	_side_buttons["menu"] = _rail_button(btns2, "MENU", func(): _toggle(menu))

	# --- Bottom dock: time controls + tools -------------------------------
	var dock := VBoxContainer.new()
	dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dock.offset_left = 8
	dock.offset_right = -8
	dock.offset_top = -122
	dock.offset_bottom = -8
	dock.add_theme_constant_override("separation", 5)
	add_child(dock)

	speedbar = load("res://ui/speed_bar.gd").new()
	speedbar.on_focus_life = func(): main.focus_life()
	speedbar.on_focus_world = func(): main.focus_world()
	dock.add_child(speedbar)

	toolbar = load("res://ui/tool_bar.gd").new()
	dock.add_child(toolbar)

	# --- Creature inspector ----------------------------------------------
	card = load("res://ui/creature_card.gd").new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.offset_left = 8
	card.offset_bottom = -130
	card.offset_top = -330
	card.visible = false
	add_child(card)

	# --- On-demand panels -------------------------------------------------
	stats = load("res://ui/stats_panel.gd").new()
	_full_panel(stats)
	stats.setup(sim)
	stats.visible = false

	tree_panel = load("res://ui/evo_tree.gd").new()
	_full_panel(tree_panel)
	tree_panel.setup(sim)
	tree_panel.visible = false

	menu = _build_menu()
	_full_panel(menu, 200)
	menu.visible = false

	debug = load("res://ui/debug_overlay.gd").new()
	debug.set_anchors_preset(Control.PRESET_TOP_LEFT)
	debug.offset_left = 8
	debug.offset_top = 80
	debug.visible = Config.show_debug
	add_child(debug)
	debug.setup(sim, main)

	EventBus.creature_selected.connect(func(c): card.show_creature(c))
	EventBus.creature_deselected.connect(func(): card.show_creature(null))
	EventBus.speed_changed.connect(_on_speed_changed)

func _pad(m: MarginContainer, l: int, r: int, t: int, b: int) -> void:
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_bottom", b)

func _rail_button(parent: Node, text: String, action: Callable) -> Button:
	var b := UITheme.text_button(text, 10, 44.0)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _full_panel(p: Control, top: int = 74) -> void:
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 10
	p.offset_right = -10
	p.offset_top = top
	p.offset_bottom = -130
	add_child(p)

func _toggle(p: Control) -> void:
	var was := p.visible
	stats.visible = false
	tree_panel.visible = false
	menu.visible = false
	p.visible = not was

func _on_speed_changed(speed: float) -> void:
	for i in GameConfig.SPEEDS.size():
		if is_equal_approx(GameConfig.SPEEDS[i], speed):
			sim.set_speed_index(i, false)
			speedbar.set_index(i)
			return

# --------------------------------------------------------------------------
# Menu
# --------------------------------------------------------------------------
func _build_menu() -> PanelContainer:
	var p := UITheme.make_panel(14, UITheme.BG_SOLID)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UITheme.label("PIXEL WORLD", 15, UITheme.TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := UITheme.text_button("×", 15, 28.0)
	close.pressed.connect(func(): p.visible = false)
	head.add_child(close)

	var info := UITheme.label("", 10, UITheme.TEXT_DIM)
	info.name = "Info"
	v.add_child(info)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 5)
	v.add_child(row1)
	var b_save := UITheme.text_button("SAVE", 11, 76.0)
	b_save.pressed.connect(func():
		SaveManager.save_world(sim)
		p.visible = false)
	row1.add_child(b_save)
	var b_load := UITheme.text_button("LOAD", 11, 76.0)
	b_load.pressed.connect(func():
		if SaveManager.has_save():
			main.load_world()
			p.visible = false
		else:
			EventBus.toast.emit("No saved world yet", UITheme.WARN))
	row1.add_child(b_load)
	var b_new := UITheme.text_button("NEW WORLD", 11, 96.0)
	b_new.pressed.connect(func():
		p.visible = false
		main.new_world(0))
	row1.add_child(b_new)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 5)
	v.add_child(row2)
	var b_dbg := UITheme.text_button("DEBUG", 11, 76.0)
	b_dbg.pressed.connect(func():
		debug.visible = not debug.visible
		Config.show_debug = debug.visible
		Config.save_settings())
	row2.add_child(b_dbg)
	var b_fx := UITheme.text_button("PARTICLES", 11, 96.0)
	b_fx.pressed.connect(func():
		Config.particles_enabled = not Config.particles_enabled
		Config.save_settings()
		EventBus.toast.emit("Particles %s" % ("on" if Config.particles_enabled else "off"),
				UITheme.ACCENT))
	row2.add_child(b_fx)
	var b_seed := UITheme.text_button("COPY SEED", 11, 96.0)
	b_seed.pressed.connect(func():
		DisplayServer.clipboard_set(str(sim.world_seed))
		EventBus.toast.emit("Seed %d copied" % sim.world_seed, UITheme.ACCENT))
	row2.add_child(b_seed)

	v.add_child(UITheme.label(
		"Pick a tool and drag on the world. Pinch to zoom, drag to pan,\n"
		+ "tap a creature to inspect it. Speed up time to watch evolution.",
		9, UITheme.TEXT_DIM))
	return p

func _process(delta: float) -> void:
	if sim == null:
		return
	_hud_timer += delta
	if _hud_timer >= 0.25:
		_hud_timer = 0.0
		hud.refresh(sim)
		minimap.set_view(main._view_rect())
		if menu.visible:
			var info := menu.find_child("Info", true, false)
			if info != null:
				info.text = "seed %d · %s · %d x %d cells\n%s · year %d · %.1f days elapsed" % [
					sim.world_seed, WorldGen.ARCHETYPE_NAMES[sim.world.archetype],
					sim.world.w, sim.world.h, sim.weather.label(), sim.climate.year,
					float(sim.climate.day) + sim.climate.day_phase]
