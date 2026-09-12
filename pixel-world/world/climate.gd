class_name Climate
extends RefCounted
## Day/night cycle, seasons and the global temperature offset, plus the ambient
## colour grade every renderer reads. One source of truth for "what time is it
## and what colour is the light".

var tick: int = 0
var _tick_frac: float = 0.0
var day: int = 0
var year: int = 0

## 0 = midnight, 0.5 = noon.
var day_phase: float = 0.25
## 0 = deep night, 1 = full daylight.
var day_factor: float = 1.0
## Seasonal offset in degrees C, and the live global offset from events.
var season_offset: float = 0.0
var event_offset: float = 0.0
var global_temp: float = 20.0

## Ambient light colour used to grade the whole frame.
var ambient: Color = Color.WHITE

const _KEY_TIMES: PackedFloat32Array = [0.0, 0.18, 0.24, 0.30, 0.50, 0.70, 0.76, 0.82, 1.0]
const _KEY_COLORS: PackedColorArray = [
	Color(0.30, 0.36, 0.62),   # midnight
	Color(0.34, 0.38, 0.62),   # late night
	Color(0.72, 0.52, 0.58),   # dawn
	Color(1.02, 0.86, 0.74),   # sunrise
	Color(1.03, 1.00, 0.96),   # noon
	Color(1.05, 0.92, 0.80),   # afternoon
	Color(1.08, 0.72, 0.52),   # sunset
	Color(0.62, 0.46, 0.60),   # dusk
	Color(0.30, 0.36, 0.62),   # midnight
]

## Advances the clock by `seconds` of simulated time and returns
## [day_rolled, year_rolled] so callers can fire calendar events.
func advance(seconds: float) -> Array:
	var day_rolled := false
	var year_rolled := false
	_tick_frac += seconds / GameConfig.TICK_DT
	var whole := int(_tick_frac)
	_tick_frac -= float(whole)
	tick += whole
	while tick >= GameConfig.TICKS_PER_DAY:
		tick -= GameConfig.TICKS_PER_DAY
		day += 1
		day_rolled = true
		if day % GameConfig.DAYS_PER_YEAR == 0:
			year += 1
			year_rolled = true
	day_phase = float(tick) / float(GameConfig.TICKS_PER_DAY)
	# Smooth daylight curve: night below the horizon, plateau at midday.
	var sun := sin((day_phase - 0.22) * TAU * 0.5 / 0.5)
	day_factor = clampf(smoothstep(-0.18, 0.35, sun), 0.0, 1.0)
	ambient = _grade(day_phase)
	# Seasons follow the year fraction.
	var season_t := float(day % GameConfig.DAYS_PER_YEAR) / float(GameConfig.DAYS_PER_YEAR)
	season_offset = sin(season_t * TAU) * 7.5
	# Night is colder than day.
	var diurnal := lerpf(-6.0, 3.5, day_factor)
	global_temp = season_offset + event_offset + diurnal
	return [day_rolled, year_rolled]

func _grade(t: float) -> Color:
	for i in range(_KEY_TIMES.size() - 1):
		if t >= _KEY_TIMES[i] and t <= _KEY_TIMES[i + 1]:
			var span: float = maxf(0.0001, _KEY_TIMES[i + 1] - _KEY_TIMES[i])
			var k: float = (t - _KEY_TIMES[i]) / span
			return _KEY_COLORS[i].lerp(_KEY_COLORS[i + 1], k)
	return _KEY_COLORS[0]

## Hour of day as a 0-23 integer, for the HUD.
func hour() -> int:
	return int(day_phase * 24.0)

func time_label() -> String:
	var h := int(day_phase * 24.0)
	var m := int((day_phase * 24.0 - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]

func is_night() -> bool:
	return day_factor < 0.22

func total_days() -> int:
	return day

func serialize() -> Dictionary:
	return {"tick": tick, "day": day, "year": year, "event_offset": event_offset}

func deserialize(d: Dictionary) -> void:
	tick = int(d.get("tick", 0))
	day = int(d.get("day", 0))
	year = int(d.get("year", 0))
	event_offset = float(d.get("event_offset", 0.0))
	advance(0.0)
