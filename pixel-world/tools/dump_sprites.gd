extends SceneTree
## Dev tool: rasterises sample creature/flora sprites to PNG for visual review.
## Run: godot --headless --script tools/dump_sprites.gd

func _initialize() -> void:
	var families := ["quadruped", "insect", "avian", "serpent", "blob", "aquatic"]
	var sheet := Image.create(PixelArt.ATLAS_W, PixelArt.TILE * families.size() * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.09, 0.12, 1.0))
	var tint: Array[Color] = [Color(0.85, 0.72, 0.35), Color(0.45, 0.85, 0.55), Color(0.55, 0.7, 0.95),
			Color(0.85, 0.4, 0.4), Color(0.7, 0.5, 0.9), Color(0.4, 0.85, 0.85)]
	for i in families.size():
		var spec := PixelArt.shape_from_traits(i, 1.0 + float(i) * 0.1, 1.0, 0.7, 100 + i * 13)
		var strip: Array = PixelArt.build_species_strip(spec)
		var body: Image = strip[0]
		var detail: Image = strip[1]
		# colourise body by tint, overlay white details
		for y in PixelArt.TILE:
			for x in PixelArt.ATLAS_W:
				var bp := body.get_pixel(x, y)
				var dp := detail.get_pixel(x, y)
				var out := Color(0.08, 0.09, 0.12, 1.0)
				if bp.a > 0.01:
					out = Color(bp.r * tint[i].r, bp.g * tint[i].g, bp.b * tint[i].b, 1.0)
				if dp.a > 0.5:
					out = Color(0.95, 0.98, 1.0, 1.0)
				sheet.set_pixel(x, i * PixelArt.TILE * 2 + y, out)
	sheet.resize(sheet.get_width() * 4, sheet.get_height() * 4, Image.INTERPOLATE_NEAREST)
	sheet.save_png("/tmp/claude-0/-home-user-AI/1d56067b-106b-510d-82ed-d255f0b7f538/scratchpad/sprites.png")

	var flora := PixelArt.build_flora_atlas()
	flora.resize(flora.get_width() * 6, flora.get_height() * 6, Image.INTERPOLATE_NEAREST)
	flora.save_png("/tmp/claude-0/-home-user-AI/1d56067b-106b-510d-82ed-d255f0b7f538/scratchpad/flora.png")
	print("dumped")
	quit()
