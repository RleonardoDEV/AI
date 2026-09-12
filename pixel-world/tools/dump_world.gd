extends SceneTree
## Dev tool: generates worlds and writes their baked albedo to PNG.
## Run: godot --headless --script tools/dump_world.gd -- <seed> [count]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var base_seed := 12345 if args.size() < 1 else int(args[0])
	var count := 4 if args.size() < 2 else int(args[1])
	var out := "/tmp/claude-0/-home-user-AI/1d56067b-106b-510d-82ed-d255f0b7f538/scratchpad/"
	var sheet := Image.create(GameConfig.WORLD_W * count, GameConfig.WORLD_H, false, Image.FORMAT_RGBA8)
	for k in count:
		var t0 := Time.get_ticks_msec()
		var world := WorldData.new()
		WorldGen.generate(world, base_seed + k * 7919)
		var dt := Time.get_ticks_msec() - t0
		var img := Image.create(world.w, world.h, false, Image.FORMAT_RGBA8)
		for y in world.h:
			for x in world.w:
				img.set_pixel(x, y, world.cell_color(y * world.w + x))
		sheet.blit_rect(img, Rect2i(0, 0, world.w, world.h), Vector2i(k * world.w, 0))
		print("seed=%d arch=%s gen=%dms land=%d water=%d flora=%d" % [
			world.world_seed, WorldGen.ARCHETYPE_NAMES[world.archetype], dt,
			world.land_cells, world.water_cells, WorldGen.last_flora.size()])
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out + "worlds.png")
	quit()
