extends Node
## Dev tool: downscales the repository screenshots so cloning stays light.
## Run: godot --headless res://tools/shrink_shots.tscn

func _ready() -> void:
	var dir := DirAccess.open("res://screenshots")
	if dir == null:
		print("no screenshots directory")
		get_tree().quit()
		return
	var total_before := 0
	var total_after := 0
	for f in dir.get_files():
		if not f.ends_with(".png"):
			continue
		var path := "res://screenshots/" + f
		var abs := ProjectSettings.globalize_path(path)
		var fa := FileAccess.open(abs, FileAccess.READ)
		if fa == null:
			continue
		total_before += fa.get_length()
		fa.close()
		var img := Image.load_from_file(abs)
		if img == null:
			continue
		# Nearest-neighbour by an exact factor keeps the pixel art crisp.
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_NEAREST)
		img.save_png(abs)
		var fb := FileAccess.open(abs, FileAccess.READ)
		if fb != null:
			total_after += fb.get_length()
			fb.close()
		print("  %s -> %dx%d" % [f, img.get_width(), img.get_height()])
	print("screenshots: %d KB -> %d KB" % [total_before / 1024, total_after / 1024])
	get_tree().quit()
