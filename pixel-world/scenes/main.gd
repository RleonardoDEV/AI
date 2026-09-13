extends Node2D
## Entry point and integration layer.
##
## Builds the world, the render stack, the camera and the UI in code — the
## scene file is a single node — so all the wiring is readable in one place and
## nothing depends on editor state. Also owns input routing: which gestures go
## to the camera and which paint with the active god tool.

const REVEAL_TIME: float = 2.9
const TOOL_INTERVAL: float = 0.045

# --- Systems --------------------------------------------------------------
var sim: Simulation
var bank: SpriteBank

# --- Render stack ---------------------------------------------------------
var world_layer: Node2D
var backdrop: Sprite2D
var terrain: TerrainRenderer
var flora_view: FloraRenderer
var entity_view: EntityRenderer
var effects: EffectsManager
var sky: SkyOverlay
var cam: CameraRig
var ui: Node

# --- Interaction ----------------------------------------------------------
var active_tool: int = WorldTools.Tool.INSPECT
var selected: Creature = null
var _tool_timer: float = 0.0
var _touch_down: bool = false
var _touch_count: int = 0
var _last_tool_pos: Vector2 = Vector2.ZERO
var _drag_distance: float = 0.0

# --- Presentation state ---------------------------------------------------
var _reveal: float = 0.0
var _shake: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _backdrop_mat: ShaderMaterial
var _frame_ms: float = 0.0

# --- Dev screenshot harness ----------------------------------------------
var _shot_path: String = ""
var _shot_times: PackedFloat32Array = PackedFloat32Array()
var _shot_index: int = 0
var _shot_speed: int = -1
var _shot_zoom: float = -1.0
var _elapsed: float = 0.0
var _cli_seed: int = 0
var _shot_focus_pop: bool = false
var _shot_ui: String = ""
var _shot_fx: String = ""
var _shot_select: bool = false
var _shot_staged: bool = false

func _ready() -> void:
	_parse_cli()
	randomize()
	var use_seed := _cli_seed if _cli_seed != 0 else randi()
	_build(use_seed)
	EventBus.screen_shake.connect(_on_shake)
	EventBus.tool_selected.connect(_on_tool_selected)
	EventBus.creature_selected.connect(func(c): selected = c; entity_view.selected = c)
	EventBus.creature_deselected.connect(func(): selected = null; entity_view.selected = null)
	EventBus.creature_died.connect(_on_creature_died)

func _parse_cli() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-at="):
			for part in a.substr(10).split(","):
				_shot_times.append(float(part))
		elif a.begins_with("--seed="):
			_cli_seed = int(a.substr(7))
		elif a.begins_with("--shot-speed="):
			_shot_speed = int(a.substr(13))
		elif a.begins_with("--shot-zoom="):
			_shot_zoom = float(a.substr(12))
		elif a == "--shot-focus=pop":
			_shot_focus_pop = true
		elif a.begins_with("--shot-ui="):
			_shot_ui = a.substr(10)
		elif a.begins_with("--shot-fx="):
			_shot_fx = a.substr(10)
		elif a == "--shot-select":
			_shot_select = true

# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------
## Builds the render stack. Pass `existing` to attach to an already-built
## simulation (used by loading), otherwise a fresh world is generated.
func _build(world_seed: int, existing: Simulation = null) -> void:
	if existing != null:
		sim = existing
		world_seed = sim.world_seed
	else:
		sim = Simulation.new()
		sim.build(world_seed)
	bank = SpriteBank.new()
	for sp in sim.registry.species:
		bank.ensure(sp)
	bank.flush()
	EventBus.species_created.connect(func(sp): bank.ensure(sp))

	world_layer = Node2D.new()
	world_layer.name = "World"
	add_child(world_layer)

	# Endless ocean behind the island, sampled in world space so its swell
	# lines up with the terrain's own water.
	backdrop = Sprite2D.new()
	backdrop.name = "OceanBackdrop"
	backdrop.centered = false
	var px := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	px.fill(Color.WHITE)
	backdrop.texture = ImageTexture.create_from_image(px)
	var span := 1400.0
	backdrop.position = Vector2(-(span - float(sim.world.w)) * 0.5, -(span - float(sim.world.h)) * 0.5)
	backdrop.scale = Vector2(span, span)
	_backdrop_mat = ShaderMaterial.new()
	_backdrop_mat.shader = load("res://rendering/shaders/ocean.gdshader")
	_backdrop_mat.set_shader_parameter("noise_tex", PixelArt.build_noise(128, world_seed + 5))
	_backdrop_mat.set_shader_parameter("world_origin", backdrop.position)
	_backdrop_mat.set_shader_parameter("backdrop_size", Vector2(span, span))
	_backdrop_mat.set_shader_parameter("world_center",
			Vector2(float(sim.world.w) * 0.5, float(sim.world.h) * 0.5))
	_backdrop_mat.set_shader_parameter("world_radius", float(sim.world.w) * 1.45)
	backdrop.material = _backdrop_mat
	world_layer.add_child(backdrop)

	terrain = TerrainRenderer.new()
	terrain.name = "Terrain"
	world_layer.add_child(terrain)
	terrain.setup(sim.world, world_seed)

	flora_view = FloraRenderer.new()
	flora_view.name = "Flora"
	world_layer.add_child(flora_view)
	flora_view.setup(sim.flora)

	entity_view = EntityRenderer.new()
	entity_view.name = "Entities"
	world_layer.add_child(entity_view)
	entity_view.setup(sim, bank)

	effects = EffectsManager.new()
	effects.name = "Effects"
	world_layer.add_child(effects)

	sky = SkyOverlay.new()
	sky.name = "Sky"
	add_child(sky)

	cam = CameraRig.new()
	cam.name = "Camera"
	add_child(cam)
	cam.setup(float(sim.world.w), float(sim.world.h))
	cam.make_current()

	ui = load("res://ui/ui_root.gd").new()
	ui.name = "UI"
	add_child(ui)
	ui.setup(self)

	if existing == null:
		sim.set_speed_index(2)
	ui.speedbar.set_index(sim.speed_index)
	_reveal = 0.0
	if _shot_speed >= 0:
		sim.set_speed_index(_shot_speed)
	if _shot_zoom > 0.0:
		cam.target_zoom = _shot_zoom
		cam.zoom = Vector2.ONE * _shot_zoom
	EventBus.world_generated.emit(world_seed)
	EventBus.toast.emit("World %d — %s" % [world_seed,
			WorldGen.ARCHETYPE_NAMES[sim.world.archetype]], Color(0.7, 0.9, 1.0))

## Discards everything and generates a fresh world.
func new_world(world_seed: int = 0) -> void:
	var s := world_seed if world_seed != 0 else randi()
	await _teardown()
	_build(s)

## Restores the saved world, replacing the current one.
func load_world() -> void:
	var loaded := SaveManager.load_world()
	if loaded == null:
		return
	await _teardown()
	_build(loaded.world_seed, loaded)

func _teardown() -> void:
	selected = null
	set_process(false)
	for node in [world_layer, ui, sky, cam]:
		if node != null and is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	world_layer = null
	ui = null
	sky = null
	cam = null
	await get_tree().process_frame
	set_process(true)

# --------------------------------------------------------------------------
# Frame
# --------------------------------------------------------------------------
func _process(delta: float) -> void:
	if sim == null or cam == null:
		return
	var t0 := Time.get_ticks_usec()
	_elapsed += delta
	_reveal = minf(1.0, _reveal + delta / REVEAL_TIME)

	var view := _view_rect()
	sim.advance(delta, view)

	# --- Ambient / weather to the renderers -------------------------------
	var climate := sim.climate
	var weather := sim.weather
	var ambient := climate.ambient
	var day := climate.day_factor
	terrain.set_ambient(ambient, day)
	terrain.set_weather(weather.rain_intensity, weather.wind, weather.cloud_amount,
			0.6 + weather.rain_intensity * 0.2)
	if _backdrop_mat != null:
		_backdrop_mat.set_shader_parameter("ambient_tint", Vector3(ambient.r, ambient.g, ambient.b))
		_backdrop_mat.set_shader_parameter("day_factor", day)
		_backdrop_mat.set_shader_parameter("cloud_amount", weather.cloud_amount)
		_backdrop_mat.set_shader_parameter("cloud_scroll", _elapsed)
		_backdrop_mat.set_shader_parameter("time_s", _elapsed)

	# Opening animation: the ground dissolves in out of noise (in the terrain
	# shader), then the plants, then the animals — so the world visibly comes
	# to life rather than simply fading up.
	var reveal_curve: float = smoothstep(0.0, 1.0, _reveal)
	terrain.set_reveal(_reveal)
	var flora_in: float = smoothstep(0.45, 0.92, _reveal)
	var life_in: float = smoothstep(0.66, 1.0, _reveal)
	flora_view.modulate = Color(ambient.r, ambient.g, ambient.b, flora_in)
	entity_view.modulate = Color(ambient.r, ambient.g, ambient.b, life_in)
	terrain.modulate = Color.WHITE
	backdrop.modulate = Color(reveal_curve, reveal_curve, reveal_curve, 1.0)

	var zoom := cam.zoom.x
	flora_view.set_view(view, zoom, weather.wind)
	entity_view.set_view(view, zoom)
	var night: float = 1.0 - day
	var golden: float = clampf(1.0 - absf(day - 0.5) * 3.4, 0.0, 1.0)
	var storm: float = 1.0 if weather.weather == WeatherSystem.W.STORM else 0.0
	sky.set_weather(weather.rain_intensity * (0.0 if weather.weather == WeatherSystem.W.SNOW else 1.0),
			weather.rain_intensity if weather.weather == WeatherSystem.W.SNOW else 0.0,
			weather.wind, night, golden, storm)

	# --- Effects ----------------------------------------------------------
	effects.set_environment(weather.wind, weather.rain_intensity,
			weather.rain_intensity if weather.weather == WeatherSystem.W.SNOW else 0.0,
			night, view)
	# Slash effect density when the world is racing: nobody can follow it.
	effects.set_budget(clampf(2.0 / maxf(1.0, sim.speed()), 0.15, 1.0))
	effects.fire_events(sim.fire.spark_events, sim.fire.smoke_events)

	# --- Camera shake -----------------------------------------------------
	if _shake > 0.01:
		_shake = maxf(0.0, _shake - delta * 26.0)
		_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * 0.06
		cam.offset = _shake_offset
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO

	# --- Tool auto-repeat while held --------------------------------------
	_tool_timer -= delta
	if _touch_down and _touch_count == 1 and active_tool != WorldTools.Tool.INSPECT:
		if _tool_timer <= 0.0:
			_tool_timer = TOOL_INTERVAL
			_apply_tool(_last_tool_pos, true)

	_frame_ms = lerpf(_frame_ms, float(Time.get_ticks_usec() - t0) / 1000.0, 0.1)

	if _shot_path != "" and _shot_index < _shot_times.size():
		if _shot_focus_pop:
			cam.center_on(sim.population_hotspot())
		# Stage the requested panel / effect shortly before the capture.
		if not _shot_staged and _elapsed >= maxf(0.0, _shot_times[_shot_index] - 0.7):
			_shot_staged = true
			_stage_shot()
		if _elapsed >= _shot_times[_shot_index]:
			_take_shot()

func _view_rect() -> Rect2:
	var vp := get_viewport_rect().size / cam.zoom.x
	return Rect2(cam.position - vp * 0.5, vp)

func _on_shake(strength: float) -> void:
	_shake = maxf(_shake, strength)

func _on_tool_selected(tool_id: int) -> void:
	active_tool = tool_id
	cam.pan_with_one_finger = tool_id == WorldTools.Tool.INSPECT
	if tool_id != WorldTools.Tool.INSPECT and selected != null:
		EventBus.creature_deselected.emit()

func _on_creature_died(c: Creature, _cause: int) -> void:
	if c == selected:
		EventBus.creature_deselected.emit()

# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_count += 1
			if _touch_count == 1:
				_touch_down = true
				_drag_distance = 0.0
				_last_tool_pos = cam.screen_to_world(t.position)
				if active_tool != WorldTools.Tool.INSPECT:
					_apply_tool(_last_tool_pos, false)
		else:
			_touch_count = maxi(0, _touch_count - 1)
			if _touch_count == 0:
				_touch_down = false
				# A tap (not a drag) with the inspect tool selects a creature.
				if active_tool == WorldTools.Tool.INSPECT and _drag_distance < 12.0:
					_pick_at(cam.screen_to_world(t.position))
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag_distance += d.relative.length()
		_last_tool_pos = cam.screen_to_world(d.position)

func _pick_at(world_pos: Vector2) -> void:
	var radius: float = maxf(3.0, 26.0 / cam.zoom.x)
	var c := entity_view.pick(world_pos, radius)
	if c != null:
		EventBus.creature_selected.emit(c)
	else:
		EventBus.creature_deselected.emit()

## Jumps the camera to the busiest part of the world.
func focus_life() -> void:
	EventBus.camera_focus_requested.emit(sim.population_hotspot(), maxf(cam.zoom.x, 7.0))

## Frames the entire world.
func focus_world() -> void:
	cam.frame_world()

## Brush radius per tool, in world cells.
func tool_radius(tool_id: int) -> float:
	match tool_id:
		WorldTools.Tool.RAIN:
			return 9.0
		WorldTools.Tool.FIRE:
			return 2.6
		WorldTools.Tool.WATER:
			return 4.0
		WorldTools.Tool.PLANT:
			return 5.0
		WorldTools.Tool.ROCK:
			return 4.0
		WorldTools.Tool.METEOR:
			return 12.0
		WorldTools.Tool.VOLCANO:
			return 10.0
		WorldTools.Tool.ICE:
			return 6.0
		WorldTools.Tool.WIND:
			return 12.0
		WorldTools.Tool.CREATURE:
			return 2.0
	return 3.0

func _apply_tool(world_pos: Vector2, repeat: bool) -> void:
	var w := sim.world
	if world_pos.x < 0.0 or world_pos.y < 0.0 or world_pos.x >= float(w.w) or world_pos.y >= float(w.h):
		return
	var ctx := sim.ctx
	var r := tool_radius(active_tool)
	match active_tool:
		WorldTools.Tool.RAIN:
			WorldTools.rain(ctx, world_pos, r, 0.35)
			if not repeat or randf() < 0.3:
				effects.splash(world_pos, 2.0)
		WorldTools.Tool.FIRE:
			WorldTools.ignite(ctx, world_pos, r, 0.85)
		WorldTools.Tool.WATER:
			WorldTools.flood(ctx, world_pos, r)
		WorldTools.Tool.PLANT:
			WorldTools.plant(ctx, world_pos, r, sim.flora)
		WorldTools.Tool.ROCK:
			WorldTools.raise_rock(ctx, world_pos, r)
		WorldTools.Tool.ICE:
			WorldTools.freeze(ctx, world_pos, r)
		WorldTools.Tool.WIND:
			var dir := Vector2.from_angle(randf() * TAU)
			if repeat:
				dir = sim.weather.wind.normalized()
			WorldTools.gust(ctx, world_pos, dir, r, 1.2)
		WorldTools.Tool.CREATURE:
			if not repeat or _tool_timer <= 0.0:
				WorldTools.spawn_life(ctx, world_pos, 1)
		WorldTools.Tool.METEOR:
			# One-shot cataclysms never auto-repeat.
			if not repeat:
				WorldTools.meteor(ctx, world_pos, 1.0)
		WorldTools.Tool.VOLCANO:
			if not repeat:
				WorldTools.erupt(ctx, world_pos, 1.0)

# --------------------------------------------------------------------------
# Dev helpers
# --------------------------------------------------------------------------
func frame_ms() -> float:
	return _frame_ms

## Dev-only: opens a panel, fires an effect or selects a creature so the
## screenshot harness can capture states that normally need touch input.
func _stage_shot() -> void:
	match _shot_ui:
		"stats":
			ui.stats.visible = true
		"tree":
			ui.tree_panel.visible = true
		"menu":
			ui.menu.visible = true
		"debug":
			ui.debug.visible = true
	if _shot_select:
		var c := entity_view.pick(cam.position, 40.0)
		if c != null:
			EventBus.creature_selected.emit(c)
	if _shot_fx != "":
		var at := cam.position
		match _shot_fx:
			"meteor":
				WorldTools.meteor(sim.ctx, at, 1.0)
			"fire":
				for k in 5:
					WorldTools.ignite(sim.ctx, at + Vector2(randf_range(-9.0, 9.0),
							randf_range(-9.0, 9.0)), 3.0, 0.9)
			"rain":
				WorldTools.rain(sim.ctx, at, 22.0, 1.0)
				sim.weather.weather = WeatherSystem.W.STORM
				sim.weather.target_rain = 0.9
				sim.weather.rain_intensity = 0.85
				sim.weather.target_cloud = 0.95
			"ice":
				WorldTools.freeze(sim.ctx, at, 16.0)
			"volcano":
				WorldTools.erupt(sim.ctx, at, 1.3)

func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _shot_path
	if _shot_times.size() > 1:
		path = _shot_path.replace(".png", "_%d.png" % _shot_index)
	img.save_png(path)
	print("shot %d -> %s (pop %d drawn %d, flora drawn %d, species %d, year %d, %s)" % [
		_shot_index, path, sim.population(), entity_view.drawn_count,
		flora_view.drawn_count, sim.species_count(), sim.climate.year,
		sim.climate.time_label()])
	_shot_index += 1
	_shot_staged = false
	if _shot_index >= _shot_times.size():
		get_tree().quit()
