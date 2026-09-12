extends PanelContainer
## Time controls (pause through 100x) plus the camera shortcuts.

var _buttons: Array[Button] = []
var _index: int = 2
var on_focus_life: Callable = Callable()
var on_focus_world: Callable = Callable()

func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel(14, UITheme.BG))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	add_child(row)
	for i in GameConfig.SPEED_LABELS.size():
		var b := UITheme.text_button(GameConfig.SPEED_LABELS[i], 12, 38.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_speed.bind(i))
		row.add_child(b)
		_buttons.append(b)
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(6, 0)
	row.add_child(sep)
	var life := UITheme.text_button("LIFE", 11, 40.0)
	life.tooltip_text = "Jump to the busiest place in the world"
	life.pressed.connect(func(): if on_focus_life.is_valid(): on_focus_life.call())
	row.add_child(life)
	var world := UITheme.text_button("ALL", 11, 36.0)
	world.tooltip_text = "Frame the whole world"
	world.pressed.connect(func(): if on_focus_world.is_valid(): on_focus_world.call())
	row.add_child(world)
	_refresh()

func _on_speed(i: int) -> void:
	_index = i
	_refresh()
	EventBus.speed_changed.emit(GameConfig.SPEEDS[i])

func set_index(i: int) -> void:
	_index = i
	_refresh()

func _refresh() -> void:
	for i in _buttons.size():
		UITheme.set_button_active(_buttons[i], i == _index,
				UITheme.WARN if i == 0 else UITheme.ACCENT)
