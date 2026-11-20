class_name WorldTimeManager
extends Node

## Central WorldTimeManager for Sydney Day/Night Cycle
## Provides continuous 24-hour in-game clock, smooth environment lighting transitions,
## sun/moon positioning, day-phase detection, and night lighting activation signals.

signal time_changed(hours: float, formatted_time: String)
signal period_changed(period_name: String)
signal activity_period_changed(period_name: String)
signal night_mode_changed(is_night: bool)
signal lighting_factor_changed(factor: float)

# Day length in real-world seconds (30 minutes default)
@export var day_length_seconds: float = 1800.0
# Current time in hours (0.0 to 24.0). The canonical Splooge world opens after dark.
@export var current_time_hours: float = 21.0
# Whether time is paused (e.g. for debugging / screenshots)
@export var time_paused: bool = false
# Time speedup multiplier (1.0 = normal, 60.0 = 1 min is 1 hr)
@export var time_multiplier: float = 1.0

var current_period: String = "night"
## Coarse, gameplay-facing period shared by every living-world system:
## morning / daytime / afternoon / evening / night. The detailed `current_period`
## remains for lighting and existing tests.
var activity_period: String = "night"
var is_night: bool = true
var lighting_factor: float = 0.0
var _lighting_emit_accum: float = 0.0

## Weather is applied here so the sun and fog have one owner. WeatherManager
## writes these factors; _apply_lighting consumes them every frame.
var weather_overcast: float = 0.0
var weather_rain: float = 0.0

# Lighting references
var world_env: WorldEnvironment
var directional_light: DirectionalLight3D
var original_env: Environment

# Period definitions
# dawn: 5.5 - 7.0
# morning: 7.0 - 11.5
# midday: 11.5 - 14.5
# afternoon: 14.5 - 17.5
# sunset: 17.5 - 19.0
# dusk: 19.0 - 20.5
# night: 20.5 - 4.5
# pre-dawn: 4.5 - 5.5

func _ready() -> void:
	add_to_group("time_managers")
	_find_lighting_nodes()
	_update_period(true)
	_apply_lighting(0.0, true)

func _find_lighting_nodes() -> void:
	var root := get_tree().root
	for env in root.find_children("*", "WorldEnvironment", true, false):
		world_env = env as WorldEnvironment
		if world_env != null and world_env.environment != null:
			# Make duplicate so we don't mutate shared global resources unintentionally
			world_env.environment = world_env.environment.duplicate()
			original_env = world_env.environment
		break
	
	for light in root.find_children("*", "DirectionalLight3D", true, false):
		directional_light = light as DirectionalLight3D
		break

func _process(delta: float) -> void:
	if not time_paused and day_length_seconds > 0.0:
		var hours_per_sec := 24.0 / day_length_seconds
		current_time_hours += hours_per_sec * delta * time_multiplier
		if current_time_hours >= 24.0:
			current_time_hours = fmod(current_time_hours, 24.0)
		elif current_time_hours < 0.0:
			current_time_hours = 24.0 + fmod(current_time_hours, 24.0)
		
		time_changed.emit(current_time_hours, get_formatted_time())
	
	_update_period(false)
	_apply_lighting(delta)

func get_formatted_time() -> String:
	var total_minutes := int(current_time_hours * 60.0)
	var hrs := (total_minutes / 60) % 24
	var mins := total_minutes % 60
	return "%02d:%02d" % [hrs, mins]

func set_time(hours: float) -> void:
	current_time_hours = fmod(hours, 24.0)
	if current_time_hours < 0.0:
		current_time_hours += 24.0
	_update_period(true)
	_apply_lighting(0.0, true)
	time_changed.emit(current_time_hours, get_formatted_time())

func _update_period(force: bool) -> void:
	var p: String = "night"
	var night: bool = true
	
	if current_time_hours >= 4.5 and current_time_hours < 5.5:
		p = "pre-dawn"
		night = true
	elif current_time_hours >= 5.5 and current_time_hours < 7.0:
		p = "dawn"
		night = false
	elif current_time_hours >= 7.0 and current_time_hours < 11.5:
		p = "morning"
		night = false
	elif current_time_hours >= 11.5 and current_time_hours < 14.5:
		p = "midday"
		night = false
	elif current_time_hours >= 14.5 and current_time_hours < 17.5:
		p = "afternoon"
		night = false
	elif current_time_hours >= 17.5 and current_time_hours < 19.0:
		p = "sunset"
		night = false
	elif current_time_hours >= 19.0 and current_time_hours < 20.5:
		p = "dusk"
		night = true
	else:
		p = "night"
		night = true
	
	if force or p != current_period:
		current_period = p
		period_changed.emit(current_period)

	var activity_p := _activity_period_for(current_time_hours)
	if force or activity_p != activity_period:
		activity_period = activity_p
		activity_period_changed.emit(activity_period)

	if force or night != is_night:
		is_night = night
		night_mode_changed.emit(is_night)


func _activity_period_for(hours: float) -> String:
	if hours >= 6.0 and hours < 11.5:
		return "morning"
	if hours >= 11.5 and hours < 15.0:
		return "daytime"
	if hours >= 15.0 and hours < 17.5:
		return "afternoon"
	if hours >= 17.5 and hours < 21.0:
		return "evening"
	return "night"


## WeatherManager calls this instead of writing sun/fog directly.
func set_weather_factors(overcast: float, rain: float) -> void:
	weather_overcast = clampf(overcast, 0.0, 1.0)
	weather_rain = clampf(rain, 0.0, 1.0)

func _apply_lighting(delta: float, force: bool = false) -> void:
	var next_lighting_factor := _night_lighting_factor(current_time_hours)
	if absf(next_lighting_factor - lighting_factor) > 0.0001:
		lighting_factor = next_lighting_factor
		# Dawn/dusk changes the factor every frame, and every emission fans out
		# to city lights plus one callback per AI vehicle. 10 Hz is visually
		# identical over a ~112 s transition and costs 6x less.
		_lighting_emit_accum += delta
		if force or _lighting_emit_accum >= 0.1:
			_lighting_emit_accum = 0.0
			lighting_factor_changed.emit(lighting_factor)

	if directional_light == null or world_env == null or world_env.environment == null:
		_find_lighting_nodes()
		if directional_light == null or world_env == null or world_env.environment == null:
			return

	var env := world_env.environment
	# Calculate sun angle based on 24h clock:
	# 6:00 is sunrise (East, pitch ~ 0)
	# 12:00 is noon (North/zenith in Southern Hemisphere, high pitch)
	# 18:00 is sunset (West, pitch ~ 0)
	# 0:00 / 24:00 is midnight (below horizon)
	var sun_progress := (current_time_hours - 6.0) / 12.0 # 0.0 at sunrise, 1.0 at sunset
	
	var sun_pitch: float = 0.0
	var sun_yaw: float = 0.0
	var light_col: Color = Color.WHITE
	var light_energy: float = 0.0
	var ambient_col: Color = Color("cfe0ea")
	var ambient_energy: float = 0.62
	var sky_top: Color = Color("4296bf")
	var sky_horizon: Color = Color("c1e7df")
	
	# Smooth transitions through clock hours
	if current_time_hours >= 6.0 and current_time_hours < 18.0:
		# Daytime sun
		var daylight_t := (current_time_hours - 6.0) / 12.0 # 0.0 -> 1.0
		# Sun moves from East (yaw 90) through North (yaw 0) to West (yaw -90)
		sun_yaw = lerpf(70.0, -70.0, daylight_t)
		# Arc height up to -65 degrees pitch at noon
		sun_pitch = -sin(daylight_t * PI) * 62.0 - 5.0
		
		if current_time_hours < 7.5:
			# Dawn / early morning
			var t := (current_time_hours - 6.0) / 1.5
			light_col = Color("ffd294").lerp(Color("fff0d0"), t)
			light_energy = lerpf(0.35, 0.9, t)
			ambient_col = Color("9aaec4").lerp(Color("cfe0ea"), t)
			ambient_energy = lerpf(0.45, 0.65, t)
			sky_top = Color("3a6b8c").lerp(Color("4296bf"), t)
			sky_horizon = Color("f3b688").lerp(Color("c1e7df"), t)
		elif current_time_hours < 15.0:
			# Morning to midday
			var t := (current_time_hours - 7.5) / 7.5
			light_col = Color("fff5e0").lerp(Color("ffffff"), t)
			light_energy = lerpf(0.9, 1.15, sin(t * PI * 0.5))
			ambient_col = Color("cfe0ea")
			ambient_energy = 0.65
			sky_top = Color("388ebd")
			sky_horizon = Color("bde4e0")
		elif current_time_hours < 17.5:
			# Afternoon
			var t := (current_time_hours - 15.0) / 2.5
			light_col = Color("ffffff").lerp(Color("ffdd9e"), t)
			light_energy = lerpf(1.1, 0.85, t)
			ambient_col = Color("cfe0ea").lerp(Color("d6d4e8"), t)
			ambient_energy = lerpf(0.65, 0.55, t)
			sky_top = Color("388ebd").lerp(Color("3f6085"), t)
			sky_horizon = Color("bde4e0").lerp(Color("f2c59b"), t)
		else:
			# Sunset (17.5 - 18.0)
			var t := (current_time_hours - 17.5) / 0.5
			light_col = Color("ff9944").lerp(Color("d94b36"), t)
			light_energy = lerpf(0.85, 0.3, t)
			ambient_col = Color("7a5d7b").lerp(Color("3b3858"), t)
			ambient_energy = lerpf(0.55, 0.38, t)
			sky_top = Color("2e3b68").lerp(Color("1b2042"), t)
			sky_horizon = Color("f57d47").lerp(Color("8f3c4d"), t)
	else:
		# Night time (18.0 to 6.0)
		# Calculate moon progress
		var night_t: float
		if current_time_hours >= 18.0:
			night_t = (current_time_hours - 18.0) / 12.0
		else:
			night_t = (current_time_hours + 6.0) / 12.0
		
		sun_yaw = lerpf(-110.0, 70.0, night_t)
		# Moon or faint night directional light
		sun_pitch = -sin(night_t * PI) * 45.0 - 5.0
		light_col = Color("9fb7d8") # Cool silver-blue moonlight
		light_energy = 0.26
		# A dark blue ambient base keeps silhouettes readable; lamps and windows
		# supply the bright local pools so the city is not uniformly grey.
		ambient_col = Color("3d4f69")
		ambient_energy = 0.32
		sky_top = Color("070d1a") # Dark navy night sky
		sky_horizon = Color("142338")
		
		# Dusk transition (18.0 - 19.5)
		if current_time_hours >= 18.0 and current_time_hours < 19.5:
			var t := (current_time_hours - 18.0) / 1.5
			light_energy = lerpf(0.3, 0.12, t)
			ambient_col = Color("3b3858").lerp(Color("536983"), t)
			ambient_energy = lerpf(0.38, 0.34, t)
			sky_top = Color("1b2042").lerp(Color("050914"), t)
			sky_horizon = Color("8f3c4d").lerp(Color("121f30"), t)
		# Pre-dawn transition (4.5 - 6.0)
		elif current_time_hours >= 4.5 and current_time_hours < 6.0:
			var t := (current_time_hours - 4.5) / 1.5
			light_energy = lerpf(0.12, 0.3, t)
			ambient_col = Color("536983").lerp(Color("586a82"), t)
			ambient_energy = lerpf(0.32, 0.45, t)
			sky_top = Color("050914").lerp(Color("26466b"), t)
			sky_horizon = Color("121f30").lerp(Color("d69372"), t)

	# Weather is layered on top of the time-of-day lighting rather than racing it.
	# This keeps one owner (this manager) for sun/sky while WeatherManager only
	# supplies the overcast and rain factors.
	var weather_shade := 1.0 - weather_overcast * 0.62
	light_energy = clampf(light_energy * weather_shade, 0.04, 1.2)
	if weather_overcast > 0.01:
		light_col = light_col.lerp(Color("a8b8c8"), clampf(weather_overcast, 0.0, 1.0))
	ambient_energy = clampf(ambient_energy * (1.0 - weather_overcast * 0.12 - weather_rain * 0.06), 0.12, 0.8)

	directional_light.rotation_degrees = Vector3(sun_pitch, sun_yaw, 0)
	directional_light.light_color = light_col
	directional_light.light_energy = light_energy

	env.ambient_light_color = ambient_col
	env.ambient_light_energy = ambient_energy
	
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		sky_mat.sky_top_color = sky_top
		sky_mat.sky_horizon_color = sky_horizon
		sky_mat.ground_horizon_color = sky_horizon.darkened(0.3)


func _night_lighting_factor(hours: float) -> float:
	var wrapped := fposmod(hours, 24.0)
	if wrapped >= 20.5 or wrapped < 4.5:
		return 1.0
	if wrapped >= 17.0:
		return _smooth_step(17.0, 20.5, wrapped)
	if wrapped >= 4.5 and wrapped < 7.0:
		return 1.0 - _smooth_step(4.5, 7.0, wrapped)
	return 0.0


func _smooth_step(edge_a: float, edge_b: float, value: float) -> float:
	var t := clampf((value - edge_a) / (edge_b - edge_a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
