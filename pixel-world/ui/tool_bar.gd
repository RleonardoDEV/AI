extends PanelContainer
## The god-tool palette. Icons are procedural pixel art tinted per tool, and
## the active tool is highlighted with its own accent colour.

const ICON_PX: int = 30

var icons: ImageTexture
var _buttons: Array[Button] = []
var _active: int = WorldTools.Tool.INSPECT

func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel(14, UITheme.BG))
	icons = PixelArt.build_icon_atlas()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	add_child(row)
	for t in WorldTools.TOOL_NAMES.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(ICON_PX + 14, ICON_PX + 16)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = WorldTools.TOOL_NAMES[t]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.set_button_active(b, t == _active, UITheme.TOOL_COLORS[t])
		b.add_theme_stylebox_override("hover",
				UITheme.panel(8, Color(0.16, 0.19, 0.26, 0.85)))
		b.pressed.connect(_on_pressed.bind(t))
		# Icon drawn by a child TextureRect so it can be tinted per tool.
		var tr := TextureRect.new()
		tr.texture = AtlasTexture.new()
		var at: AtlasTexture = tr.texture
		at.atlas = icons
		at.region = PixelArt.icon_region(t)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.modulate = UITheme.TOOL_COLORS[t]
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.offset_top = 3
		tr.offset_bottom = -6
		b.add_child(tr)
		# Tiny caption so the tools are learnable.
		var cap := UITheme.label(WorldTools.TOOL_SHORT[t], 7, UITheme.TEXT_DIM)
		cap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.offset_top = -11
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(cap)
		row.add_child(b)
		_buttons.append(b)

func _on_pressed(tool_id: int) -> void:
	_active = tool_id
	for i in _buttons.size():
		UITheme.set_button_active(_buttons[i], i == tool_id, UITheme.TOOL_COLORS[i])
	EventBus.tool_selected.emit(tool_id)

func active_tool() -> int:
	return _active
