extends Node2D
## Entry point: builds the world, the render stack and the camera, then hands
## control to the simulation. Everything is constructed in code — the scene
## file is a single node — so wiring stays in one readable place and nothing
## depends on editor state.

var world: WorldData
var terrain: TerrainRenderer
var cam: CameraRig

var world_seed: int = 0

# Screenshot harness (dev): --shot=PATH --shot-at=1,5,20 --shot-seed=N
var _shot_path: String = ""
var _shot_times: PackedFloat32Array = PackedFloat32Array()
var _shot_index: int = 0
var _elapsed: float = 0.0

func _ready() -> void:
	_parse_cli()
	randomize()
	if world_seed == 0:
		world_seed = randi()
	_build_world(world_seed)

func _parse_cli() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-at="):
			for part in a.substr(10).split(","):
				_shot_times.append(float(part))
		elif a.begins_with("--shot-seed="):
			world_seed = int(a.substr(12))

func _build_world(s: int) -> void:
	world = WorldData.new()
	WorldGen.generate(world, s)

	terrain = TerrainRenderer.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(world, s)

	cam = CameraRig.new()
	cam.name = "Camera"
	add_child(cam)
	cam.setup(float(world.w), float(world.h))
	cam.make_current()

	# Placeholder ambient until the climate system drives it.
	terrain.set_ambient(Color(1.0, 0.98, 0.94), 1.0)
	terrain.set_weather(0.0, Vector2(0.25, 0.08), 0.35, 0.6)
	EventBus.world_generated.emit(s)

func _process(delta: float) -> void:
	_elapsed += delta
	if _shot_path != "" and _shot_index < _shot_times.size():
		if _elapsed >= _shot_times[_shot_index]:
			_take_shot()

func _take_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := _shot_path
	if _shot_times.size() > 1:
		path = _shot_path.replace(".png", "_%d.png" % _shot_index)
	img.save_png(path)
	print("shot %d -> %s" % [_shot_index, path])
	_shot_index += 1
	if _shot_index >= _shot_times.size():
		get_tree().quit()
