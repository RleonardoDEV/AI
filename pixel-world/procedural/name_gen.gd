class_name NameGen
extends RefCounted
## Deterministic binomial-ish species names, so a lineage is recognisable in
## the stats panel and the evolutionary tree.

const PREFIX: PackedStringArray = [
	"Vel", "Kra", "Zeph", "Mor", "Thal", "Ny", "Ore", "Sil", "Dra", "Um",
	"Cal", "Ig", "Vor", "Lum", "Eph", "Rho", "Xan", "Ser", "Bry", "Kel",
	"Nim", "Phae", "Quor", "Tes", "Vash", "Ael", "Bor", "Cyn", "Dus", "Eb",
]
const MIDDLE: PackedStringArray = [
	"o", "a", "i", "u", "ae", "yo", "ei", "ou", "ia", "e",
]
const SUFFIX: PackedStringArray = [
	"drix", "thin", "mora", "pex", "nis", "val", "kar", "lith", "phus", "ren",
	"tox", "gan", "mir", "saur", "vex", "cyte", "pod", "form", "nax", "quil",
]
const EPITHET: PackedStringArray = [
	"minor", "major", "agilis", "ferox", "placidus", "nocturnus", "solaris",
	"gracilis", "robustus", "vagans", "littoralis", "montanus", "silvaticus",
	"aridus", "glacialis", "profundus", "rapax", "sapiens", "mutabilis", "primus",
]

static func species_name(id: int, world_seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = (id * 7919) ^ (world_seed * 104729)
	var s := PREFIX[rng.randi() % PREFIX.size()]
	if rng.randf() < 0.55:
		s += MIDDLE[rng.randi() % MIDDLE.size()]
	s += SUFFIX[rng.randi() % SUFFIX.size()]
	return s

static func epithet(id: int, world_seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = (id * 31337) ^ (world_seed * 15485863)
	return EPITHET[rng.randi() % EPITHET.size()]
