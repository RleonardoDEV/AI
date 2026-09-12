class_name PixelArt
extends RefCounted
## Procedural pixel-art generation. No external image assets ship with the
## game: every sprite, icon and gradient is rasterised at runtime from a
## gene-derived shape description.
##
## Creature sprites are rasterised as *implicit shapes* sampled in a rotated
## local frame. That gives clean 8-direction pixel art (nothing is rotated at
## runtime, so the art stays pixel-perfect) and lets body proportions follow
## DNA: a fast, lean, aggressive lineage physically looks like one.

const TILE: int = 16
const DIRS: int = 8
const FRAMES: int = 2
const ATLAS_COLS: int = DIRS * FRAMES          # 16 tiles per species row
const ATLAS_W: int = ATLAS_COLS * TILE         # 256
const ROW_H: int = TILE * 2                    # body row + detail row
const MAX_EXTENT: float = 7.4                  # keeps shapes inside the tile

# Body families (silhouette archetypes).
enum Family { QUADRUPED, INSECT, AVIAN, SERPENT, BLOB, AQUATIC }

# Material ids produced by the implicit shape sampler.
enum M { NONE, BODY, LIMB, SPIKE, EYE, WING, FIN, HORN }

const NB_X: PackedInt32Array = [1, -1, 0, 0]
const NB_Y: PackedInt32Array = [0, 0, 1, -1]

# --------------------------------------------------------------------------
# Shape specification
# --------------------------------------------------------------------------
## Builds a shape description from phenotype traits. Deterministic: identical
## inputs always produce an identical silhouette, so a species looks stable
## across saves while its descendants drift visibly.
static func shape_from_traits(family: int, size: float, speed: float,
		aggression: float, variant_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	var s: float = clampf(size, 0.4, 2.0)
	var spec := {
		"family": family,
		"body_len": 2.4 + s * 1.9,
		"body_wid": 1.7 + s * 1.3,
		"head_r": 1.1 + s * 0.55,
		"tail_len": 0.0,
		"legs": 0,
		"leg_span": 1.0,
		"spikes": 0,
		"horns": false,
		"wings": false,
		"fins": false,
		"antennae": false,
		"neck": 0.0,
		"pattern": rng.randi_range(0, 3),
		"pattern_scale": rng.randf_range(1.0, 2.2),
	}
	match family:
		Family.QUADRUPED:
			spec.legs = 4
			spec.tail_len = 1.2 + s * 0.8
			spec.neck = 0.3 + s * 0.25
			spec.spikes = 3 if aggression > 0.66 else 0
			spec.horns = aggression > 0.5
		Family.INSECT:
			spec.body_len = 1.6 + s * 1.0
			spec.body_wid = 1.2 + s * 0.7
			spec.head_r = 0.85 + s * 0.35
			spec.legs = 6
			spec.leg_span = 1.35
			spec.antennae = true
		Family.AVIAN:
			spec.body_len = 2.2 + s * 1.4
			spec.body_wid = 1.5 + s * 1.0
			spec.head_r = 1.0 + s * 0.45
			spec.legs = 2
			spec.wings = true
			spec.tail_len = 1.4 + s * 0.9
		Family.SERPENT:
			spec.body_len = 3.0 + s * 1.2
			spec.body_wid = 1.6 + s * 0.85
			spec.head_r = 1.25 + s * 0.5
			spec.tail_len = 2.2 + s * 0.8
			spec.spikes = 4 if aggression > 0.5 else 2
		Family.BLOB:
			spec.body_len = 2.2 + s * 1.6
			spec.body_wid = 2.2 + s * 1.6
			spec.head_r = 0.0
			spec.spikes = 6 if aggression > 0.45 else 0
		Family.AQUATIC:
			spec.body_len = 2.4 + s * 1.5
			spec.body_wid = 1.3 + s * 0.8
			spec.head_r = 0.9 + s * 0.4
			spec.tail_len = 1.6 + s * 0.9
			spec.fins = true

	# Faster lineages grow longer limbs and leaner bodies.
	var sp: float = clampf(speed, 0.3, 2.0)
	spec.leg_span = float(spec.leg_span) * (0.8 + sp * 0.35)
	spec.body_wid = float(spec.body_wid) * (1.1 - sp * 0.08)

	# Clamp the silhouette so no feature is clipped by the tile.
	var fwd: float = float(spec.body_len) * 0.82 + float(spec.neck) + float(spec.head_r) + 1.2
	var back: float = float(spec.body_len) * 0.55 + float(spec.tail_len)
	var over: float = maxf(fwd, back) / MAX_EXTENT
	if over > 1.0:
		spec.body_len = float(spec.body_len) / over
		spec.tail_len = float(spec.tail_len) / over
		spec.head_r = float(spec.head_r) / over
	spec.body_wid = minf(float(spec.body_wid), MAX_EXTENT - 2.2)
	return spec

# --------------------------------------------------------------------------
# Rasterisation
# --------------------------------------------------------------------------
## Evaluates the silhouette at a point in *local* space (+X = forward,
## origin = body centre) and returns a material id.
static func _sample(spec: Dictionary, lx: float, ly: float, frame: int) -> int:
	var bl: float = spec.body_len
	var bw: float = spec.body_wid
	var hr: float = spec.head_r
	var aly := absf(ly)
	var gait := 1.0 if frame == 0 else -1.0
	var hx: float = bl * 0.78 + float(spec.neck)

	# Horns / mandibles: two short prongs ahead of the head.
	if spec.horns and hr > 0.01:
		var tipx := hx + hr * 0.9
		if lx > tipx - 0.4 and lx < tipx + 1.25 and aly > hr * 0.35 and aly < hr * 1.05:
			return M.HORN

	# Antennae for insects.
	if spec.antennae:
		var ax := hx + hr * 0.7
		if lx > ax and lx < ax + 1.6 and aly > 0.35 and aly < 1.5 and absf(lx - ax - aly) < 0.9:
			return M.LIMB

	# Head disc (with eye sockets punched into its front flanks).
	if hr > 0.01:
		var dxh := lx - hx
		if dxh * dxh + ly * ly <= hr * hr:
			if dxh > hr * 0.05 and aly > hr * 0.3 and aly < hr * 0.78:
				return M.EYE
			return M.BODY

	# Defensive spines: protrude past the flanks, so aggression is legible.
	if int(spec.spikes) > 0:
		var n: int = spec.spikes
		for i in n:
			var t := -0.62 + 1.24 * (float(i) / maxf(1.0, float(n - 1)))
			var sx := t * bl * 0.86
			if absf(lx - sx) < 0.52:
				var edge_y := bw * sqrt(maxf(0.0, 1.0 - (sx / bl) * (sx / bl)))
				if aly > edge_y - 0.2 and aly < edge_y + 1.35:
					return M.SPIKE

	# Body ellipse.
	var ex := lx / bl
	var ey := ly / bw
	if ex * ex + ey * ey <= 1.0:
		return M.BODY

	# Tail: tapering, gait-animated strip behind the body.
	var tl: float = spec.tail_len
	if tl > 0.01 and lx < -bl * 0.5:
		var d := -lx - bl * 0.5
		if d <= tl:
			var tprog := clampf(d / tl, 0.0, 1.0)
			var wig := sin(tprog * 2.6 + gait * 1.1) * (0.35 + tprog * 1.1)
			var thick := lerpf(bw * 0.62, 0.55, tprog)
			if absf(ly - wig) <= thick:
				return M.BODY

	# Legs: paired stubs along the flanks, alternating by gait frame.
	var legs: int = spec.legs
	if legs > 0:
		var span: float = spec.leg_span
		var pairs := int(legs / 2)
		for i in pairs:
			var t := 0.0 if pairs == 1 else (-0.55 + 1.1 * (float(i) / float(pairs - 1)))
			var phase := gait if (i % 2 == 0) else -gait
			var legx := t * bl + phase * 0.6
			var legy := bw * 0.72 + span * 0.75
			if absf(lx - legx) <= 0.55 and absf(aly - legy) <= 0.72:
				return M.LIMB

	# Wings: swept, flapping triangles.
	if spec.wings:
		var flap := 1.0 if frame == 0 else 0.55
		var inner := bw * 0.55
		var outer := inner + 1.2 + flap * 1.7
		# Wing root sits forward of centre; the plane sweeps backwards.
		var wx := (lx - bl * 0.18) * 0.75
		if aly > inner and aly < outer:
			var sweep := (aly - inner) / maxf(0.5, outer - inner)
			var cx := -sweep * 1.5
			if absf(wx - cx) < bl * (0.95 - sweep * 0.3):
				return M.WING

	# Pectoral + caudal fins.
	if spec.fins:
		if lx < -bl * 0.3 and lx > -bl * 0.95 and aly > bw * 0.55 and aly < bw * 1.45:
			return M.FIN
		if lx > bl * 0.1 and lx < bl * 0.6 and aly > bw * 0.6 and aly < bw * 1.25:
			return M.FIN

	return M.NONE

## Rasterises one tile (one direction, one frame) into `img` at `origin`.
## Grey levels are chosen so `modulate` by the DNA colour yields a shaded,
## outlined creature: ~0.3 rim, ~0.65 flank, ~0.98 spine highlight.
static func _blit_tile(img: Image, detail: Image, spec: Dictionary,
		dir_index: int, frame: int, origin: Vector2i) -> void:
	var ang := float(dir_index) * TAU / float(DIRS)
	var ca := cos(-ang)
	var sa := sin(-ang)
	var c := float(TILE) * 0.5
	var mat := PackedByteArray()
	mat.resize(TILE * TILE)
	var shade := PackedFloat32Array()
	shade.resize(TILE * TILE)
	var best_hi := -1.0
	var best_hi_idx := -1

	for py in TILE:
		for px in TILE:
			var ox := float(px) - c + 0.5
			var oy := float(py) - c + 0.5
			var lx := ox * ca - oy * sa
			var ly := ox * sa + oy * ca
			var m := _sample(spec, lx, ly, frame)
			var idx := py * TILE + px
			mat[idx] = m
			match m:
				M.BODY:
					# Round the body across its minor axis.
					var t := clampf(absf(ly) / maxf(0.7, float(spec.body_wid)), 0.0, 1.0)
					var g := lerpf(0.98, 0.62, t * t)
					g += clampf(lx / maxf(1.0, float(spec.body_len)), -0.25, 0.45) * 0.09
					# Genetic coat pattern.
					var pat: int = spec.pattern
					var ps: float = spec.pattern_scale
					if pat == 1 and int(floor(lx * ps + 16.0)) % 2 == 0:
						g *= 0.8
					elif pat == 2 and (int(floor(lx * ps + 16.0)) + int(floor(ly * ps + 16.0))) % 3 == 0:
						g *= 0.78
					elif pat == 3 and absf(ly) < float(spec.body_wid) * 0.35:
						g *= 1.06
					shade[idx] = clampf(g, 0.06, 1.0)
					# Track the brightest upper-front pixel for the specular glint.
					var hi := g - oy * 0.06 + lx * 0.04
					if hi > best_hi:
						best_hi = hi
						best_hi_idx = idx
				M.LIMB:
					shade[idx] = 0.45
				M.SPIKE:
					shade[idx] = 1.0
				M.HORN:
					shade[idx] = 0.9
				M.WING:
					shade[idx] = 0.58
				M.FIN:
					shade[idx] = 0.52

	# Outline pass: solid pixels touching empty space become a dark rim.
	var out_shade := shade.duplicate()
	for py in TILE:
		for px in TILE:
			var idx := py * TILE + px
			var m2: int = mat[idx]
			if m2 == M.NONE:
				continue
			var edge := false
			for k in 4:
				var nx: int = px + NB_X[k]
				var ny: int = py + NB_Y[k]
				if nx < 0 or ny < 0 or nx >= TILE or ny >= TILE:
					edge = true
					break
				if mat[ny * TILE + nx] == M.NONE:
					edge = true
					break
			if edge:
				# Near-black rim: `modulate` is a multiply, so a very low grey
				# stays dark whatever colour the creature's DNA gives it. This is
				# what keeps a silhouette readable over grass, sand or water.
				out_shade[idx] = 0.10 if m2 == M.BODY else shade[idx] * 0.34

	for py in TILE:
		for px in TILE:
			var idx := py * TILE + px
			var m3: int = mat[idx]
			if m3 == M.NONE:
				continue
			if m3 == M.EYE:
				img.set_pixel(origin.x + px, origin.y + py, Color(0.14, 0.14, 0.17, 1.0))
			else:
				var g: float = out_shade[idx]
				img.set_pixel(origin.x + px, origin.y + py, Color(g, g, g, 1.0))

	# One unmodulated specular pixel, drawn only at close zoom (see renderer).
	if best_hi_idx >= 0:
		var hx2 := best_hi_idx % TILE
		var hy2 := int(best_hi_idx / TILE)
		detail.set_pixel(origin.x + hx2, origin.y + hy2, Color(1, 1, 1, 0.55))

## Builds the 16-tile body strip and matching detail strip for one species.
## Returns [body_image, detail_image], each ATLAS_W x TILE.
static func build_species_strip(spec: Dictionary) -> Array:
	var body := Image.create(ATLAS_W, TILE, false, Image.FORMAT_RGBA8)
	var detail := Image.create(ATLAS_W, TILE, false, Image.FORMAT_RGBA8)
	body.fill(Color(0, 0, 0, 0))
	detail.fill(Color(0, 0, 0, 0))
	for d in DIRS:
		for f in FRAMES:
			var col := d * FRAMES + f
			_blit_tile(body, detail, spec, d, f, Vector2i(col * TILE, 0))
	return [body, detail]

# --------------------------------------------------------------------------
# Flora
# --------------------------------------------------------------------------
const TREE_TILE: int = 16
const TREE_STAGES: int = 4
const TREE_VARIANTS: int = 6

## Top-down canopies: concentric noise-perturbed blobs with a rim, a lit side
## and a trunk pixel peeking out. Returns one image, variants x stages grid.
static func build_flora_atlas() -> Image:
	var img := Image.create(TREE_TILE * TREE_STAGES, TREE_TILE * TREE_VARIANTS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	for v in TREE_VARIANTS:
		rng.seed = 9001 + v * 7717
		var lobes := rng.randi_range(3, 6)
		var lobe_ang := PackedFloat32Array()
		var lobe_r := PackedFloat32Array()
		for i in lobes:
			lobe_ang.append(rng.randf() * TAU)
			lobe_r.append(rng.randf_range(0.45, 0.95))
		var hue_shift := rng.randf_range(-0.035, 0.045)
		var is_conifer := v >= 4
		for s in TREE_STAGES:
			var scale := lerpf(0.28, 1.0, float(s) / float(TREE_STAGES - 1))
			var ox := s * TREE_TILE
			var oy := v * TREE_TILE
			var c := float(TREE_TILE) * 0.5
			var rad := (float(TREE_TILE) * 0.46) * scale
			for py in TREE_TILE:
				for px in TREE_TILE:
					var dx := float(px) - c + 0.5
					var dy := float(py) - c + 0.5
					var dist := sqrt(dx * dx + dy * dy)
					var ang := atan2(dy, dx)
					var bump := 0.0
					for i in lobes:
						var da: float = absf(wrapf(ang - lobe_ang[i], -PI, PI))
						bump += lobe_r[i] * exp(-da * da * 2.6)
					var r_eff := rad * (0.62 + bump * 0.42)
					if is_conifer:
						# Star-ish conifer silhouette
						r_eff = rad * (0.55 + 0.45 * absf(cos(ang * 3.0)))
					if dist <= r_eff:
						var t := dist / maxf(0.001, r_eff)
						var lit := clampf(0.5 - (dx + dy) * 0.055, 0.0, 1.0)
						var g := lerpf(0.95, 0.52, t) * lerpf(0.82, 1.06, lit)
						var col := Color(
							clampf(0.16 + hue_shift + (1.0 - t) * 0.10, 0.0, 1.0),
							clampf(0.42 + (1.0 - t) * 0.30, 0.0, 1.0),
							clampf(0.19 + hue_shift * 0.5 + (1.0 - t) * 0.09, 0.0, 1.0),
							1.0)
						col = Color(col.r * g * 1.35, col.g * g * 1.25, col.b * g * 1.3, 1.0)
						if t > 0.88:
							col = Color(col.r * 0.45, col.g * 0.45, col.b * 0.5, 1.0)
						img.set_pixel(ox + px, oy + py, col)
			# Trunk shadow pixel below the canopy
			if s >= 1:
				var tx := ox + int(c)
				var ty := oy + int(c + rad * 0.65)
				if ty < oy + TREE_TILE:
					img.set_pixel(tx, ty, Color(0.22, 0.15, 0.11, 1.0))
	return img

const BUSH_TILE: int = 8
## Small shrubs / flowers / cacti: 8 variants in one row.
static func build_shrub_atlas() -> Image:
	var n := 8
	var img := Image.create(BUSH_TILE * n, BUSH_TILE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	for v in n:
		rng.seed = 4242 + v * 991
		var ox := v * BUSH_TILE
		var base := Color(0.18, 0.44, 0.21)
		if v >= 6:
			base = Color(0.30, 0.44, 0.20) # dry scrub
		var blobs := rng.randi_range(2, 4)
		for b in blobs:
			var bx := rng.randf_range(2.0, float(BUSH_TILE) - 2.0)
			var by := rng.randf_range(2.0, float(BUSH_TILE) - 2.0)
			var br := rng.randf_range(1.1, 2.0)
			for py in BUSH_TILE:
				for px in BUSH_TILE:
					var dx := float(px) - bx + 0.5
					var dy := float(py) - by + 0.5
					if dx * dx + dy * dy <= br * br:
						var lit := clampf(0.6 - (dx + dy) * 0.14, 0.15, 1.1)
						img.set_pixel(ox + px, py, Color(base.r * lit * 1.5, base.g * lit * 1.35, base.b * lit * 1.4, 1.0))
		# flower dots
		if v >= 2 and v <= 5:
			var palette: Array[Color] = [Color(0.95, 0.85, 0.35), Color(0.92, 0.42, 0.55),
					Color(0.65, 0.55, 0.95), Color(0.95, 0.95, 0.92)]
			var fc: Color = palette[v - 2]
			for k in rng.randi_range(1, 3):
				var fx := rng.randi_range(1, BUSH_TILE - 2)
				var fy := rng.randi_range(1, BUSH_TILE - 2)
				if img.get_pixel(ox + fx, fy).a > 0.1:
					img.set_pixel(ox + fx, fy, fc)
	return img

# --------------------------------------------------------------------------
# Gradients / particle textures
# --------------------------------------------------------------------------
## Soft radial falloff used additively for fire, lava and lamp glow.
static func build_glow(size: int = 64, power: float = 2.4) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - c + 0.5) / c
			var dy := (float(y) - c + 0.5) / c
			var d := clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var a := pow(d, power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

## Hard-edged pixel dot used for most particles (keeps the pixel-art feel).
static func build_dot(size: int = 4) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

## Seamless value-noise texture used by shaders for clouds, waves and wind.
static func build_noise(size: int = 128, noise_seed: int = 1337) -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = noise_seed
	n.frequency = 0.028
	n.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n2.seed = noise_seed + 77
	n2.frequency = 0.09
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			# Tileable via 4-corner blend
			var fx := float(x)
			var fy := float(y)
			var s := float(size)
			var a := n.get_noise_2d(fx, fy)
			var b := n.get_noise_2d(fx - s, fy)
			var c2 := n.get_noise_2d(fx, fy - s)
			var d := n.get_noise_2d(fx - s, fy - s)
			var u := fx / s
			var v := fy / s
			var val := lerpf(lerpf(a, b, u), lerpf(c2, d, u), v)
			var hi := n2.get_noise_2d(fx, fy) * 0.5 + 0.5
			img.set_pixel(x, y, Color(val * 0.5 + 0.5, hi, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	return tex

# --------------------------------------------------------------------------
# UI icons
# --------------------------------------------------------------------------
## Tool glyphs, authored as small bitmaps so the whole UI stays asset-free.
## '#' body, '*' highlight, '+' shadow, '.' empty.
const ICON_SIZE: int = 12
const ICON_ART: Array = [
	# INSPECT - magnifier
	["...#####....", "..#.....#...", ".#.......#..", ".#.......#..",
	 ".#.......#..", "..#.....#...", "...#####....", "......##....",
	 ".......##...", "........##..", ".........##.", "............"],
	# RAIN - cloud with drops
	["............", "...#####....", "..#######...", ".#########..",
	 ".#########..", "..#######...", "............", "..+..+..+...",
	 "..+..+..+...", "...+..+..+..", "............", "............"],
	# FIRE - flame
	[".....#......", "....##......", "....###.....", "...#####....",
	 "..###*###...", "..##***##...", ".###***###..", ".###***###..",
	 "..##***##...", "...######...", "....####....", "............"],
	# WATER - droplet
	[".....#......", ".....#......", "....###.....", "....###.....",
	 "...#####....", "..#######...", "..###*###...", ".####*####..",
	 ".#########..", "..#######...", "...#####....", "............"],
	# PLANT - sprout
	["............", "......#.....", "...##.#.##..", "..####.####.",
	 "..###...###.", "...##.#.##..", "......#.....", "......#.....",
	 ".....###....", "....#####...", "...+++++++..", "............"],
	# ROCK
	["............", "............", "....####....", "...######...",
	 "..###****#..", ".###*****#..", ".##*****##..", ".#*******#..",
	 ".#########..", "..#######...", "............", "............"],
	# METEOR - bolide with trail
	[".+..........", "..+.........", "...++.......", "....++......",
	 ".....###....", "....#####...", "....##*##...", "....#####...",
	 ".....###....", "............", "............", "............"],
	# VOLCANO - cone with ejecta
	["....*.*.....", ".....*......", "....###.....", "...#####....",
	 "...##*##....", "..###*###...", "..#######...", ".#########..",
	 ".#########..", "###########.", "############", "............"],
	# ICE - snowflake
	[".....#......", "...#.#.#....", "....###.....", ".#..###..#..",
	 "..#.###.#...", "#####*#####.", "..#.###.#...", ".#..###..#..",
	 "....###.....", "...#.#.#....", ".....#......", "............"],
	# WIND - streaks
	["............", "..####......", ".#....##....", "......##....",
	 "..#####.....", "............", "....######..", "...#.....##.",
	 ".........##.", "....#####...", "............", "............"],
	# CREATURE - paw print
	["............", "..##....##..", ".####..####.", ".####..####.",
	 "..##....##..", "............", "..########..", ".##########.",
	 ".##########.", "..########..", "...######...", "............"],
]

## One row of icons, ICON_SIZE tall. Glyphs are drawn in greys so the UI can
## modulate each button with its own accent colour.
static func build_icon_atlas() -> ImageTexture:
	var n := ICON_ART.size()
	var img := Image.create(ICON_SIZE * n, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in n:
		var art: Array = ICON_ART[i]
		for y in mini(ICON_SIZE, art.size()):
			var row: String = art[y]
			for x in mini(ICON_SIZE, row.length()):
				var ch := row[x]
				var col := Color(0, 0, 0, 0)
				match ch:
					"#":
						col = Color(1, 1, 1, 1)
					"*":
						col = Color(0.72, 0.72, 0.72, 1)
					"+":
						col = Color(0.5, 0.5, 0.5, 1)
				if col.a > 0.0:
					img.set_pixel(i * ICON_SIZE + x, y, col)
	return ImageTexture.create_from_image(img)

static func icon_region(tool_id: int) -> Rect2:
	return Rect2(float(tool_id * ICON_SIZE), 0.0, float(ICON_SIZE), float(ICON_SIZE))
