class_name SimStats
extends RefCounted
## Live counters plus a downsampled history used by the stats panel graphs.

var births: int = 0
var deaths: int = 0
var attacks: int = 0
var deaths_by_cause: PackedInt32Array = PackedInt32Array()
var peak_population: int = 0
var mutations: int = 0

## Ring history, one sample every HISTORY_EVERY ticks.
const HISTORY_LEN: int = 180
const HISTORY_EVERY: int = 240
var hist_population: PackedFloat32Array = PackedFloat32Array()
var hist_species: PackedFloat32Array = PackedFloat32Array()
var hist_temp: PackedFloat32Array = PackedFloat32Array()
var hist_veg: PackedFloat32Array = PackedFloat32Array()
var hist_predators: PackedFloat32Array = PackedFloat32Array()
var _last_sample_tick: int = -HISTORY_EVERY

# Cached rollups refreshed by Simulation (avoids recomputing per frame).
var avg_generation: float = 1.0
var max_generation: int = 1
var avg_speed_gene: float = 0.0
var avg_size_gene: float = 0.0
var herbivores: int = 0
var carnivores: int = 0
var omnivores: int = 0
var total_vegetation: float = 0.0
var avg_temperature: float = 0.0

func _init() -> void:
	deaths_by_cause.resize(9)

func note_birth() -> void:
	births += 1

func note_death(cause: int) -> void:
	deaths += 1
	if cause >= 0 and cause < deaths_by_cause.size():
		deaths_by_cause[cause] += 1

func note_attack() -> void:
	attacks += 1

func note_mutations(n: int) -> void:
	mutations += n

func maybe_sample(tick: int, population: int, species_count: int, temp: float,
		veg: float, predators: int) -> void:
	if tick - _last_sample_tick < HISTORY_EVERY:
		return
	_last_sample_tick = tick
	_push(hist_population, float(population))
	_push(hist_species, float(species_count))
	_push(hist_temp, temp)
	_push(hist_veg, veg)
	_push(hist_predators, float(predators))

func _push(arr: PackedFloat32Array, v: float) -> void:
	arr.append(v)
	if arr.size() > HISTORY_LEN:
		arr.remove_at(0)

func serialize() -> Dictionary:
	return {
		"births": births, "deaths": deaths, "attacks": attacks,
		"causes": deaths_by_cause, "peak": peak_population, "mutations": mutations,
		"h_pop": hist_population, "h_spec": hist_species, "h_temp": hist_temp,
		"h_veg": hist_veg, "h_pred": hist_predators,
	}

func deserialize(d: Dictionary) -> void:
	births = int(d.get("births", 0))
	deaths = int(d.get("deaths", 0))
	attacks = int(d.get("attacks", 0))
	deaths_by_cause = PackedInt32Array(d.get("causes", deaths_by_cause))
	if deaths_by_cause.size() < 9:
		deaths_by_cause.resize(9)
	peak_population = int(d.get("peak", 0))
	mutations = int(d.get("mutations", 0))
	hist_population = PackedFloat32Array(d.get("h_pop", PackedFloat32Array()))
	hist_species = PackedFloat32Array(d.get("h_spec", PackedFloat32Array()))
	hist_temp = PackedFloat32Array(d.get("h_temp", PackedFloat32Array()))
	hist_veg = PackedFloat32Array(d.get("h_veg", PackedFloat32Array()))
	hist_predators = PackedFloat32Array(d.get("h_pred", PackedFloat32Array()))
