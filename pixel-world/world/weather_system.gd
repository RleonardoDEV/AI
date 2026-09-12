class_name WeatherSystem
extends RefCounted
## Weather state machine, wind field and the random world events.
##
## Weather is not decoration: rain fills puddles and stops fires, drought
## starves regrowth, cold snaps push whole populations toward the equator, and
## a lightning strike in a dry season can burn a continent's forests down. The
## ecosystem has to answer for all of it.

enum W { CLEAR, CLOUDY, OVERCAST, RAIN, STORM, SNOW }
const W_NAMES: PackedStringArray = ["Clear", "Cloudy", "Overcast", "Rain", "Storm", "Snow"]

enum E { NONE, DROUGHT, DELUGE, WILDFIRE, COLD_SNAP, HEAT_WAVE, METEOR_SHOWER, ERUPTION, BLOOM }
const E_NAMES: PackedStringArray = [
	"", "Drought", "Deluge", "Wildfire", "Cold Snap", "Heat Wave",
	"Meteor Shower", "Volcanic Eruption", "Great Bloom",
]
const E_BLURB: PackedStringArray = [
	"",
	"The rains have failed. Rivers shrink and grasslands wither.",
	"Endless rain. Rivers swell and fires drown.",
	"Fire races through the dry country.",
	"A bitter cold rolls in from the poles.",
	"Blistering heat settles over the land.",
	"Rocks are falling from the sky.",
	"The mountain has opened.",
	"Warm rain and long days: everything grows.",
]

var weather: int = W.CLEAR
var weather_timer: float = 30.0
var rain_intensity: float = 0.0
var target_rain: float = 0.0
var cloud_amount: float = 0.25
var target_cloud: float = 0.25
var wind: Vector2 = Vector2(0.25, 0.08)
var _wind_target: Vector2 = Vector2(0.25, 0.08)
var lightning_cooldown: float = 6.0

var event_id: int = E.NONE
var event_timer: float = 0.0
var event_cooldown: float = 120.0
var events_fired: int = 0
var event_history: Array[Dictionary] = []

var _rain_accum: float = 0.0
var _meteor_accum: float = 0.0

func label() -> String:
	if event_id != E.NONE:
		return E_NAMES[event_id]
	return W_NAMES[weather]

# --------------------------------------------------------------------------
func update(ctx: SimContext, dt: float, water_sys: WaterSystem, growth: GrowthSystem) -> void:
	var climate := ctx.climate

	# ------------------------------------------------------------- wind
	if ctx.rng.randf() < dt * 0.08:
		_wind_target = Vector2.from_angle(ctx.rng.randf() * TAU) * ctx.rng.randf_range(0.05, 0.95)
	wind = wind.lerp(_wind_target, clampf(dt * 0.25, 0.0, 1.0))
	if weather == W.STORM:
		wind = wind.normalized() * maxf(wind.length(), 0.85)

	# ---------------------------------------------------------- weather
	weather_timer -= dt
	if weather_timer <= 0.0:
		_pick_weather(ctx)
	rain_intensity = lerpf(rain_intensity, target_rain, clampf(dt * 0.35, 0.0, 1.0))
	cloud_amount = lerpf(cloud_amount, target_cloud, clampf(dt * 0.2, 0.0, 1.0))

	# --------------------------------------------------------- rainfall
	if rain_intensity > 0.03:
		_rain_accum += dt * rain_intensity * 210.0
		var drops := int(_rain_accum)
		_rain_accum -= float(drops)
		var world := ctx.world
		var snowing: bool = weather == W.SNOW
		for k in mini(drops, 220):
			var x := ctx.rng.randi_range(0, world.w - 1)
			var y := ctx.rng.randi_range(0, world.h - 1)
			var i := y * world.w + x
			if Terrain.is_water(world.terrain[i]):
				continue
			if snowing or world.temperature[i] < 0.5:
				world.snow[i] = minf(1.0, world.snow[i] + 0.16)
				world.fire[i] = maxf(0.0, world.fire[i] - 0.3)
				world.mark_dirty(i)
			else:
				world.add_water(i, 0.12 + rain_intensity * 0.18)
				if world.fire[i] > 0.0:
					world.fire[i] = maxf(0.0, world.fire[i] - 0.45)

	# -------------------------------------------------------- lightning
	if weather == W.STORM:
		lightning_cooldown -= dt
		if lightning_cooldown <= 0.0:
			lightning_cooldown = ctx.rng.randf_range(3.5, 14.0)
			_strike_lightning(ctx)

	# ----------------------------------------------------------- events
	if event_id != E.NONE:
		event_timer -= dt
		_tick_event(ctx, dt, water_sys, growth)
		if event_timer <= 0.0:
			_end_event(ctx, water_sys, growth)
	else:
		event_cooldown -= dt
		if event_cooldown <= 0.0:
			_start_random_event(ctx, water_sys, growth)

	# Weather nudges the global temperature a little.
	var weather_temp := 0.0
	match weather:
		W.RAIN:
			weather_temp = -2.0
		W.STORM:
			weather_temp = -3.5
		W.SNOW:
			weather_temp = -5.0
		W.OVERCAST:
			weather_temp = -1.0
	climate.event_offset = lerpf(climate.event_offset, _event_temp_offset() + weather_temp,
			clampf(dt * 0.3, 0.0, 1.0))

func _pick_weather(ctx: SimContext) -> void:
	var r := ctx.rng.randf()
	var cold: bool = ctx.climate.global_temp < -1.0
	# Event-driven weather overrides the natural chain.
	if event_id == E.DROUGHT:
		weather = W.CLEAR if r < 0.8 else W.CLOUDY
	elif event_id == E.DELUGE:
		weather = W.STORM if r < 0.45 else W.RAIN
	elif cold and r < 0.45:
		weather = W.SNOW
	else:
		match weather:
			W.CLEAR:
				weather = W.CLEAR if r < 0.45 else W.CLOUDY
			W.CLOUDY:
				weather = W.CLEAR if r < 0.35 else (W.OVERCAST if r < 0.8 else W.RAIN)
			W.OVERCAST:
				weather = W.CLOUDY if r < 0.3 else (W.RAIN if r < 0.85 else W.STORM)
			W.RAIN:
				weather = W.OVERCAST if r < 0.45 else (W.STORM if r < 0.65 else W.CLOUDY)
			W.STORM:
				weather = W.RAIN if r < 0.6 else W.OVERCAST
			W.SNOW:
				weather = W.OVERCAST if r < 0.5 else W.SNOW
	match weather:
		W.CLEAR:
			target_rain = 0.0
			target_cloud = 0.12
			weather_timer = ctx.rng.randf_range(50.0, 160.0)
		W.CLOUDY:
			target_rain = 0.0
			target_cloud = 0.42
			weather_timer = ctx.rng.randf_range(40.0, 110.0)
		W.OVERCAST:
			target_rain = 0.04
			target_cloud = 0.68
			weather_timer = ctx.rng.randf_range(30.0, 90.0)
		W.RAIN:
			target_rain = 0.45
			target_cloud = 0.80
			weather_timer = ctx.rng.randf_range(30.0, 80.0)
		W.STORM:
			target_rain = 0.9
			target_cloud = 0.95
			weather_timer = ctx.rng.randf_range(20.0, 55.0)
		W.SNOW:
			target_rain = 0.35
			target_cloud = 0.75
			weather_timer = ctx.rng.randf_range(35.0, 95.0)
	EventBus.weather_changed.emit(weather)

func _strike_lightning(ctx: SimContext) -> void:
	var world := ctx.world
	for attempt in 14:
		var x := ctx.rng.randi_range(2, world.w - 3)
		var y := ctx.rng.randi_range(2, world.h - 3)
		var i := y * world.w + x
		if Terrain.FLAMMABILITY[world.terrain[i]] < 0.3:
			continue
		if world.water[i] > 0.2 or world.snow[i] > 0.2:
			continue
		var p := Vector2(float(x) + 0.5, float(y) + 0.5)
		EventBus.screen_flash.emit(Color(0.85, 0.92, 1.0), 0.55)
		EventBus.fx_burst.emit(p, 10, 6.0)
		# Wet storms often strike without igniting anything.
		if rain_intensity < 0.65 and ctx.rng.randf() < 0.55:
			WorldTools.ignite(ctx, p, 2.0, 0.8)
		return

# --------------------------------------------------------------------------
# Events
# --------------------------------------------------------------------------
func _start_random_event(ctx: SimContext, water_sys: WaterSystem, growth: GrowthSystem) -> void:
	var pool: PackedInt32Array = [E.DROUGHT, E.DELUGE, E.WILDFIRE, E.COLD_SNAP,
			E.HEAT_WAVE, E.METEOR_SHOWER, E.BLOOM]
	# Eruptions only where there is already volcanic ground.
	if _find_volcanic(ctx) >= 0:
		pool.append(E.ERUPTION)
	event_id = pool[ctx.rng.randi() % pool.size()]
	events_fired += 1
	match event_id:
		E.DROUGHT:
			event_timer = ctx.rng.randf_range(160.0, 320.0)
			growth.growth_mul = 0.28
			water_sys.evaporation_mul = 3.2
		E.DELUGE:
			event_timer = ctx.rng.randf_range(90.0, 180.0)
			growth.growth_mul = 1.5
			water_sys.evaporation_mul = 0.35
		E.WILDFIRE:
			event_timer = ctx.rng.randf_range(40.0, 90.0)
			_seed_wildfire(ctx)
		E.COLD_SNAP:
			event_timer = ctx.rng.randf_range(120.0, 240.0)
			growth.growth_mul = 0.5
		E.HEAT_WAVE:
			event_timer = ctx.rng.randf_range(120.0, 240.0)
			water_sys.evaporation_mul = 2.2
			growth.growth_mul = 0.7
		E.METEOR_SHOWER:
			event_timer = ctx.rng.randf_range(30.0, 70.0)
			_meteor_accum = 0.0
		E.ERUPTION:
			event_timer = ctx.rng.randf_range(50.0, 110.0)
			var vi := _find_volcanic(ctx)
			if vi >= 0:
				var vp := Vector2(float(vi % ctx.world.w) + 0.5, float(int(vi / ctx.world.w)) + 0.5)
				WorldTools.erupt(ctx, vp, ctx.rng.randf_range(0.7, 1.4))
		E.BLOOM:
			event_timer = ctx.rng.randf_range(140.0, 260.0)
			growth.growth_mul = 2.4
	event_history.append({
		"id": event_id, "year": ctx.climate.year, "day": ctx.climate.day,
		"name": E_NAMES[event_id],
	})
	if event_history.size() > 40:
		event_history.remove_at(0)
	EventBus.world_event_started.emit(event_id, E_NAMES[event_id])
	EventBus.toast.emit("%s — %s" % [E_NAMES[event_id], E_BLURB[event_id]], _event_color())

func _tick_event(ctx: SimContext, dt: float, water_sys: WaterSystem, growth: GrowthSystem) -> void:
	match event_id:
		E.METEOR_SHOWER:
			_meteor_accum += dt
			if _meteor_accum > 6.0:
				_meteor_accum = 0.0
				var p := Vector2(ctx.rng.randf_range(6.0, float(ctx.world.w) - 7.0),
						ctx.rng.randf_range(6.0, float(ctx.world.h) - 7.0))
				WorldTools.meteor(ctx, p, ctx.rng.randf_range(0.45, 1.0))
		E.WILDFIRE:
			# Keep the front alive while the event lasts.
			if ctx.world.burning_cells.size() < 12 and ctx.rng.randf() < dt * 0.4:
				_seed_wildfire(ctx)
		E.ERUPTION:
			if ctx.rng.randf() < dt * 0.25:
				var vi := _find_volcanic(ctx)
				if vi >= 0:
					var vp := Vector2(float(vi % ctx.world.w) + 0.5, float(int(vi / ctx.world.w)) + 0.5)
					var off := Vector2.from_angle(ctx.rng.randf() * TAU) * ctx.rng.randf_range(2.0, 10.0)
					WorldTools.ignite(ctx, vp + off, 2.5, 0.8)
					EventBus.fx_burst.emit(vp, 8, 6.0)

func _end_event(ctx: SimContext, water_sys: WaterSystem, growth: GrowthSystem) -> void:
	EventBus.world_event_ended.emit(event_id)
	event_id = E.NONE
	event_timer = 0.0
	growth.growth_mul = 1.0
	water_sys.evaporation_mul = 1.0
	event_cooldown = ctx.rng.randf_range(150.0, 420.0)

func _event_temp_offset() -> float:
	match event_id:
		E.COLD_SNAP:
			return -10.0
		E.HEAT_WAVE:
			return 9.0
		E.DROUGHT:
			return 5.0
		E.DELUGE:
			return -3.0
		E.ERUPTION:
			return 4.0
		E.BLOOM:
			return 2.0
	return 0.0

func _event_color() -> Color:
	match event_id:
		E.DROUGHT, E.HEAT_WAVE:
			return Color(1.0, 0.72, 0.35)
		E.DELUGE:
			return Color(0.55, 0.75, 1.0)
		E.WILDFIRE, E.ERUPTION:
			return Color(1.0, 0.45, 0.25)
		E.COLD_SNAP:
			return Color(0.7, 0.88, 1.0)
		E.METEOR_SHOWER:
			return Color(1.0, 0.85, 0.5)
		E.BLOOM:
			return Color(0.6, 1.0, 0.6)
	return Color.WHITE

func _seed_wildfire(ctx: SimContext) -> void:
	var world := ctx.world
	for attempt in 40:
		var x := ctx.rng.randi_range(3, world.w - 4)
		var y := ctx.rng.randi_range(3, world.h - 4)
		var i := y * world.w + x
		if world.veg[i] < 0.35 or Terrain.FLAMMABILITY[world.terrain[i]] < 0.5:
			continue
		WorldTools.ignite(ctx, Vector2(float(x), float(y)), 2.5, 0.85)
		return

func _find_volcanic(ctx: SimContext) -> int:
	var world := ctx.world
	var n := world.w * world.h
	# Sampled search: volcanic ground is contiguous, so probes find it fast.
	for attempt in 220:
		var i := ctx.rng.randi_range(0, n - 1)
		if world.terrain[i] == Terrain.T.LAVA or world.biome[i] == Biome.B.VOLCANIC:
			return i
	return -1

func serialize() -> Dictionary:
	return {
		"weather": weather, "timer": weather_timer, "rain": rain_intensity,
		"cloud": cloud_amount, "wind": wind, "event": event_id,
		"event_timer": event_timer, "cooldown": event_cooldown,
		"fired": events_fired, "history": event_history,
	}

func deserialize(d: Dictionary) -> void:
	weather = int(d.get("weather", W.CLEAR))
	weather_timer = float(d.get("timer", 30.0))
	rain_intensity = float(d.get("rain", 0.0))
	target_rain = rain_intensity
	cloud_amount = float(d.get("cloud", 0.25))
	target_cloud = cloud_amount
	wind = d.get("wind", Vector2(0.25, 0.08))
	_wind_target = wind
	event_id = int(d.get("event", E.NONE))
	event_timer = float(d.get("event_timer", 0.0))
	event_cooldown = float(d.get("cooldown", 120.0))
	events_fired = int(d.get("fired", 0))
	event_history.clear()
	for h in d.get("history", []):
		event_history.append(h)
