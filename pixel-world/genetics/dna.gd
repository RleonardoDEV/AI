class_name DNA
extends RefCounted
## Genome representation and genetic operators.
##
## A genome is a flat PackedFloat32Array of NUM_GENES normalised-ish values
## with per-gene bounds and mutation sigma. Keeping it as a packed array (not
## an object graph) means a creature's genome is 64 bytes, crossover is a tight
## loop, and serialisation is a single blob.

enum G {
	SPEED,          # locomotion top speed
	SIZE,           # body mass: energy capacity, strength, draw scale
	VISION,         # perception radius
	AGGRESSION,     # willingness to attack
	METABOLISM,     # energy burn rate (and how fast it must eat)
	FERTILITY,      # reproduction drive growth
	LIFESPAN,       # maximum age in simulated days
	TEMP_PREF,      # preferred ambient temperature (deg C)
	DIET,           # 0 herbivore .. 0.5 omnivore .. 1 carnivore
	HUE,            # colour genes: visible evolution
	SAT,
	VAL,
	SOCIAL,         # flocking / group cohesion
	FEAR,           # flight threshold
	STAMINA,        # sprint reserve and endurance
	AQUATIC,        # tolerance for water
}

const NUM_GENES: int = 16

const NAMES: PackedStringArray = [
	"Speed", "Size", "Vision", "Aggression", "Metabolism", "Fertility",
	"Lifespan", "Temp Pref", "Diet", "Hue", "Saturation", "Value",
	"Social", "Fear", "Stamina", "Aquatic",
]

const MIN: PackedFloat32Array = [
	0.35, 0.35, 3.0, 0.0, 0.45, 0.15, 6.0, -14.0, 0.0, 0.0, 0.15, 0.35,
	0.0, 0.0, 0.3, 0.0,
]
const MAX: PackedFloat32Array = [
	2.40, 2.10, 30.0, 1.0, 1.90, 1.00, 90.0, 38.0, 1.0, 1.0, 1.00, 1.00,
	1.0, 1.0, 2.0, 1.0,
]
## Standard deviation of a mutation step, per gene.
const SIGMA: PackedFloat32Array = [
	0.085, 0.075, 1.05, 0.055, 0.070, 0.050, 3.20, 1.35, 0.045, 0.035, 0.035, 0.030,
	0.055, 0.055, 0.075, 0.045,
]

## Genes that matter for deciding whether a lineage has become a new species.
const TAXONOMIC_WEIGHT: PackedFloat32Array = [
	1.0, 1.2, 0.5, 1.0, 0.6, 0.4, 0.35, 0.5, 1.6, 0.5, 0.25, 0.25,
	0.5, 0.35, 0.35, 1.1,
]

static func random_genome(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(NUM_GENES)
	for i in NUM_GENES:
		g[i] = rng.randf_range(MIN[i], MAX[i])
	return g

## Builds a genome around an archetype: `bias` maps gene index -> 0..1 target
## with a small spread, which is how the starting species are seeded.
static func from_profile(profile: Dictionary, rng: RandomNumberGenerator,
		spread: float = 0.08) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(NUM_GENES)
	for i in NUM_GENES:
		var t: float = profile.get(i, 0.5)
		t = clampf(t + rng.randfn(0.0, spread), 0.0, 1.0)
		g[i] = lerpf(MIN[i], MAX[i], t)
	return g

## Per-gene uniform crossover with blending: each gene either comes from one
## parent or is averaged, which preserves discrete traits while still letting
## quantitative ones converge.
static func crossover(a: PackedFloat32Array, b: PackedFloat32Array,
		rng: RandomNumberGenerator) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	g.resize(NUM_GENES)
	for i in NUM_GENES:
		var r := rng.randf()
		if r < 0.42:
			g[i] = a[i]
		elif r < 0.84:
			g[i] = b[i]
		else:
			var k := rng.randf()
			g[i] = lerpf(a[i], b[i], k)
	return g

## Gaussian mutation. `rate` is the per-gene probability of a step; a rare
## "macro" mutation takes a much larger jump, which is what actually produces
## new species rather than slow drift.
static func mutate(g: PackedFloat32Array, rng: RandomNumberGenerator,
		rate: float = 0.22, macro_chance: float = 0.02) -> int:
	var count := 0
	for i in NUM_GENES:
		if rng.randf() < rate:
			var sigma: float = SIGMA[i]
			if rng.randf() < macro_chance:
				sigma *= 6.0
			g[i] = clampf(g[i] + rng.randfn(0.0, sigma), MIN[i], MAX[i])
			count += 1
	return count

## Normalised genetic distance, weighted by taxonomic significance.
static func distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var acc := 0.0
	var wsum := 0.0
	for i in NUM_GENES:
		var span: float = maxf(0.0001, MAX[i] - MIN[i])
		var d: float = (a[i] - b[i]) / span
		var w: float = TAXONOMIC_WEIGHT[i]
		acc += d * d * w
		wsum += w
	return sqrt(acc / wsum)

## Running mean update, used to keep a species centroid current.
static func blend_into(centroid: PackedFloat32Array, g: PackedFloat32Array, k: float) -> void:
	for i in NUM_GENES:
		centroid[i] = lerpf(centroid[i], g[i], k)

static func norm(g: PackedFloat32Array, i: int) -> float:
	return clampf((g[i] - MIN[i]) / maxf(0.0001, MAX[i] - MIN[i]), 0.0, 1.0)

## Phenotype colour.
##
## Diet selects a hue band and the hue gene varies within it, so trophic role
## is readable at a glance while lineages still drift apart visually. The
## bands deliberately avoid grass-green: plant eaters coloured like the ground
## they stand on are invisible, which was the first thing the screenshots
## showed. Plant eaters therefore run cyan-to-violet and meat eaters
## amber-to-crimson — both read cleanly over grass, sand, rock and snow.
static func color_of(g: PackedFloat32Array) -> Color:
	var diet: float = clampf(g[G.DIET], 0.0, 1.0)
	# Three discrete trophic bands rather than one continuous ramp: a ramp
	# necessarily passes through green and cyan, which are exactly the colours
	# of grass and water.
	var band_center := 0.72   # plant eaters: blue -> violet -> magenta
	var band_span := 0.15
	if diet >= 0.62:
		band_center = 0.005  # meat eaters: crimson -> orange
		band_span = 0.06
	elif diet >= 0.38:
		band_center = 0.13   # omnivores: amber -> gold
		band_span = 0.055
	var hue := fposmod(band_center + (g[G.HUE] - 0.5) * band_span * 2.0, 1.0)
	var sat: float = clampf(g[G.SAT] * 0.36 + 0.50, 0.0, 1.0)
	var val: float = clampf(g[G.VAL] * 0.38 + 0.70, 0.0, 1.0)
	return Color.from_hsv(hue, sat, val)

static func describe(g: PackedFloat32Array, i: int) -> String:
	return "%s %.2f" % [NAMES[i], g[i]]

static func diet_label(diet: float) -> String:
	if diet < 0.33:
		return "Herbivore"
	if diet < 0.66:
		return "Omnivore"
	return "Carnivore"
