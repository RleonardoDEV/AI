class_name Species
extends RefCounted
## A named lineage. Species are *emergent*: the registry spawns one whenever a
## newborn's genome drifts far enough from its parent species centroid, and
## records who it descended from, which is what the evolutionary tree draws.

var id: int = 0
var name: String = ""
var epithet: String = ""
var family: int = 0                  # PixelArt.Family silhouette
var centroid: PackedFloat32Array     # running mean genome
var founder_genome: PackedFloat32Array
var parent_id: int = -1
var children: PackedInt32Array = PackedInt32Array()
var sprite_slot: int = 0
var founded_tick: int = 0
var founded_year: int = 0
var founder_generation: int = 1

# Live counters
var population: int = 0
var peak_population: int = 0
var total_born: int = 0
var total_died: int = 0
var extinct: bool = false
var extinct_year: int = -1
var color: Color = Color.WHITE

func full_name() -> String:
	return "%s %s" % [name, epithet]

func diet() -> float:
	return centroid[DNA.G.DIET]

func diet_label() -> String:
	return DNA.diet_label(diet())

func serialize() -> Dictionary:
	return {
		"id": id, "name": name, "epithet": epithet, "family": family,
		"centroid": centroid, "founder": founder_genome, "parent": parent_id,
		"children": children, "slot": sprite_slot, "tick": founded_tick,
		"year": founded_year, "gen": founder_generation,
		"born": total_born, "died": total_died, "peak": peak_population,
		"extinct": extinct, "extinct_year": extinct_year,
	}

static func deserialize(d: Dictionary) -> Species:
	var s := Species.new()
	s.id = int(d.get("id", 0))
	s.name = String(d.get("name", "?"))
	s.epithet = String(d.get("epithet", ""))
	s.family = int(d.get("family", 0))
	s.centroid = PackedFloat32Array(d.get("centroid", PackedFloat32Array()))
	s.founder_genome = PackedFloat32Array(d.get("founder", s.centroid))
	s.parent_id = int(d.get("parent", -1))
	s.children = PackedInt32Array(d.get("children", PackedInt32Array()))
	s.sprite_slot = int(d.get("slot", 0))
	s.founded_tick = int(d.get("tick", 0))
	s.founded_year = int(d.get("year", 0))
	s.founder_generation = int(d.get("gen", 1))
	s.total_born = int(d.get("born", 0))
	s.total_died = int(d.get("died", 0))
	s.peak_population = int(d.get("peak", 0))
	s.extinct = bool(d.get("extinct", false))
	s.extinct_year = int(d.get("extinct_year", -1))
	s.color = DNA.color_of(s.centroid)
	return s
