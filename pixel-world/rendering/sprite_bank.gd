class_name SpriteBank
extends RefCounted
## One texture holds every species' 8-direction sprite strip. New species are
## rasterised into a free slot and the atlas is re-uploaded once — creature
## drawing then costs a single texture bind for the whole population.

var atlas_img: Image
var detail_img: Image
var atlas_tex: ImageTexture
var detail_tex: ImageTexture
var _dirty: bool = false
var _built_slots: Dictionary = {}

func _init() -> void:
	var h := GameConfig.MAX_SPECIES_SLOTS * PixelArt.TILE
	atlas_img = Image.create(PixelArt.ATLAS_W, h, false, Image.FORMAT_RGBA8)
	detail_img = Image.create(PixelArt.ATLAS_W, h, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color(0, 0, 0, 0))
	detail_img.fill(Color(0, 0, 0, 0))
	atlas_tex = ImageTexture.create_from_image(atlas_img)
	detail_tex = ImageTexture.create_from_image(detail_img)

## Rasterises a species silhouette into its slot (idempotent per genome).
func ensure(sp: Species) -> void:
	if _built_slots.get(sp.sprite_slot, -1) == sp.id:
		return
	var g := sp.centroid
	var spec := PixelArt.shape_from_traits(
		sp.family,
		g[DNA.G.SIZE],
		g[DNA.G.SPEED],
		g[DNA.G.AGGRESSION],
		sp.id * 7717 + 13)
	var strip: Array = PixelArt.build_species_strip(spec)
	var y := sp.sprite_slot * PixelArt.TILE
	var rect := Rect2i(0, 0, PixelArt.ATLAS_W, PixelArt.TILE)
	atlas_img.blit_rect(strip[0], rect, Vector2i(0, y))
	detail_img.blit_rect(strip[1], rect, Vector2i(0, y))
	_built_slots[sp.sprite_slot] = sp.id
	_dirty = true

func flush() -> void:
	if not _dirty:
		return
	atlas_tex.update(atlas_img)
	detail_tex.update(detail_img)
	_dirty = false

## Source rect for one slot / direction / animation frame.
func region(slot: int, dir_index: int, frame: int) -> Rect2:
	var col := (dir_index % PixelArt.DIRS) * PixelArt.FRAMES + (frame % PixelArt.FRAMES)
	return Rect2(float(col * PixelArt.TILE), float(slot * PixelArt.TILE),
			float(PixelArt.TILE), float(PixelArt.TILE))
