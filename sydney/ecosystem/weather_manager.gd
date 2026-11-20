class_name WeatherManager
extends Node3D

## Central weather and environmental atmosphere manager for Sydney.
## Controls clear skies, overcast conditions, light rain and heavy downpours.
## Adjusts sun, sky, distance haze, road/facade wetness shaders, rain particles,
## and ambient weather audio.

signal weather_changed(weather_name: String)
signal wetness_changed(wetness: float)
signal rain_intensity_changed(intensity: float)

enum WeatherType { CLEAR, OVERCAST, LIGHT_RAIN, HEAVY_RAIN }

const WEATHER_NAMES := ["clear", "overcast", "light_rain", "heavy_rain"]

@export var weather_state: int = WeatherType.CLEAR
@export var auto_weather_cycle: bool = true
@export var weather_duration_min: float = 240.0 # 4 minutes per weather block
@export var weather_duration_max: float = 600.0 # 10 minutes max

var current_weather_name: String = "clear"
var wetness: float = 0.0 # 0.0 = bone dry, 1.0 = soaked with puddles
var rain_intensity: float = 0.0 # 0.0 = no rain, 1.0 = heavy downpour
var overcast_factor: float = 0.0 # 0.0 = clear sun, 1.0 = heavy cloud cover
var wind_strength: float = 0.15 # 0.0 = calm, 1.0 = stormy gale

var _target_wetness: float = 0.0
var _target_rain: float = 0.0
var _target_overcast: float = 0.0
var _target_wind: float = 0.15

var _weather_timer: float = 300.0
var _thunder_timer: float = 0.0
var _shader_update_timer: float = 0.0
var _time_manager: Node = null

# Node references
var world_env: WorldEnvironment
var directional_light: DirectionalLight3D
var player_ref: Node3D
var camera_ref: Camera3D

# Visual effects
var rain_particles: GPUParticles3D
var rain_material: ParticleProcessMaterial
var _asphalt_materials: Array[ShaderMaterial] = []
var _facade_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	add_to_group("weather_managers")
	_find_environment_nodes()
	_create_rain_particles()
	set_weather(WeatherType.CLEAR, true)


func setup(player: Node3D) -> void:
	player_ref = player
	_find_environment_nodes()
	_index_materials()


func _find_environment_nodes() -> void:
	var root := get_tree().root
	for env in root.find_children("*", "WorldEnvironment", true, false):
		world_env = env as WorldEnvironment
		break
	for light in root.find_children("*", "DirectionalLight3D", true, false):
		directional_light = light as DirectionalLight3D
		break


func _index_materials() -> void:
	_asphalt_materials.clear()
	_facade_materials.clear()
	var root := get_tree().root
	for mesh_node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mesh_node as MeshInstance3D
		var mat = mesh_inst.material_override
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			if sm.shader != null:
				var path := sm.shader.resource_path
				if "asphalt" in path:
					_asphalt_materials.append(sm)
				elif "facade" in path or mesh_inst.is_in_group("facade_surfaces"):
					_facade_materials.append(sm)


func _create_rain_particles() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.name = "RainParticles"
	rain_particles.amount = 1200
	rain_particles.lifetime = 1.2
	rain_particles.preprocess = 0.5
	rain_particles.visibility_aabb = AABB(Vector3(-30, -15, -30), Vector3(60, 30, 60))

	rain_material = ParticleProcessMaterial.new()
	rain_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rain_material.emission_box_extents = Vector3(25.0, 0.5, 25.0)
	rain_material.direction = Vector3(0.12, -1.0, 0.05).normalized()
	rain_material.spread = 4.0
	rain_material.initial_velocity_min = 28.0
	rain_material.initial_velocity_max = 36.0
	rain_material.gravity = Vector3(0, -9.8, 0)
	rain_material.color = Color(0.78, 0.88, 0.98, 0.42)
	rain_particles.process_material = rain_material

	# Long thin streak quad for rain droplet
	var ribbon := RibbonTrailMesh.new()
	ribbon.size = 0.04
	ribbon.section_length = 0.35
	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.38)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rain_particles.draw_pass_1 = ribbon
	rain_particles.material_override = drop_mat
	rain_particles.emitting = false
	add_child(rain_particles)


func set_weather(type: int, immediate: bool = false) -> void:
	weather_state = clampi(type, 0, WeatherType.HEAVY_RAIN)
	current_weather_name = WEATHER_NAMES[weather_state]

	match weather_state:
		WeatherType.CLEAR:
			_target_overcast = 0.0
			_target_rain = 0.0
			_target_wetness = 0.0
			_target_wind = 0.15
		WeatherType.OVERCAST:
			_target_overcast = 0.75
			_target_rain = 0.0
			_target_wetness = 0.05
			_target_wind = 0.3
		WeatherType.LIGHT_RAIN:
			_target_overcast = 0.85
			_target_rain = 0.45
			_target_wetness = 0.65
			_target_wind = 0.45
		WeatherType.HEAVY_RAIN:
			_target_overcast = 1.0
			_target_rain = 1.0
			_target_wetness = 1.0
			_target_wind = 0.85

	if immediate:
		overcast_factor = _target_overcast
		rain_intensity = _target_rain
		wetness = _target_wetness
		wind_strength = _target_wind
		_apply_weather_effects()

	weather_changed.emit(current_weather_name)
	wetness_changed.emit(wetness)
	rain_intensity_changed.emit(rain_intensity)


func set_weather_by_name(weather_name: String, immediate: bool = false) -> void:
	var idx := WEATHER_NAMES.find(weather_name.to_lower())
	if idx >= 0:
		set_weather(idx, immediate)


func _process(delta: float) -> void:
	if auto_weather_cycle:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			_pick_next_weather()
			_weather_timer = randf_range(weather_duration_min, weather_duration_max)

	# Smoothly blend parameters
	var blend_rate := delta * 0.25 # approx 4-6s smooth transition
	overcast_factor = move_toward(overcast_factor, _target_overcast, blend_rate)
	rain_intensity = move_toward(rain_intensity, _target_rain, blend_rate)
	wind_strength = move_toward(wind_strength, _target_wind, blend_rate)

	# Drying takes longer than wetting
	var wet_rate := blend_rate if _target_wetness > wetness else (blend_rate * 0.35)
	wetness = move_toward(wetness, _target_wetness, wet_rate)

	_apply_weather_effects()
	_update_rain_position()

	# Periodic thunder in heavy rain
	if weather_state == WeatherType.HEAVY_RAIN and rain_intensity > 0.6:
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_trigger_thunder()
			_thunder_timer = randf_range(16.0, 45.0)


func _pick_next_weather() -> void:
	var roll := randf()
	if weather_state == WeatherType.CLEAR:
		if roll < 0.55: set_weather(WeatherType.OVERCAST)
		elif roll < 0.85: set_weather(WeatherType.CLEAR)
		else: set_weather(WeatherType.LIGHT_RAIN)
	elif weather_state == WeatherType.OVERCAST:
		if roll < 0.40: set_weather(WeatherType.CLEAR)
		elif roll < 0.80: set_weather(WeatherType.LIGHT_RAIN)
		else: set_weather(WeatherType.HEAVY_RAIN)
	elif weather_state == WeatherType.LIGHT_RAIN:
		if roll < 0.45: set_weather(WeatherType.HEAVY_RAIN)
		elif roll < 0.80: set_weather(WeatherType.OVERCAST)
		else: set_weather(WeatherType.CLEAR)
	else: # HEAVY_RAIN
		if roll < 0.65: set_weather(WeatherType.LIGHT_RAIN)
		else: set_weather(WeatherType.OVERCAST)


func _update_rain_position() -> void:
	if rain_particles == null:
		return
	var target_pos := Vector3.ZERO
	if player_ref != null and is_instance_valid(player_ref):
		target_pos = player_ref.global_position
	elif camera_ref != null and is_instance_valid(camera_ref):
		target_pos = camera_ref.global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			camera_ref = cam
			target_pos = cam.global_position

	rain_particles.global_position = target_pos + Vector3(0.0, 14.0, 0.0)

	if rain_intensity > 0.02:
		if not rain_particles.emitting:
			rain_particles.emitting = true
		rain_particles.amount_ratio = clampf(rain_intensity, 0.1, 1.0)
		if rain_material != null:
			var wind_drift := Vector3(wind_strength * 0.4, -1.0, wind_strength * 0.2).normalized()
			rain_material.direction = wind_drift
			rain_material.initial_velocity_min = 26.0 + wind_strength * 12.0
			rain_material.initial_velocity_max = 34.0 + wind_strength * 16.0
	else:
		if rain_particles.emitting:
			rain_particles.emitting = false


func _apply_weather_effects() -> void:
	# 1. Update shaders
	_shader_update_timer += get_process_delta_time()
	if _shader_update_timer >= 0.1:
		_shader_update_timer = 0.0
		if _asphalt_materials.is_empty() or _facade_materials.is_empty():
			_index_materials()
		for mat in _asphalt_materials:
			mat.set_shader_parameter("wetness", wetness)
		for mat in _facade_materials:
			mat.set_shader_parameter("wetness", wetness)

	# 2. Supply weather factors to WorldTimeManager, the sole owner of the sun.
	# Writing light_energy here used to be overwritten by the time manager on
	# the very next frame, so overcast skies never actually darkened the city.
	if not is_instance_valid(_time_manager):
		var time_mgrs := get_tree().get_nodes_in_group("time_managers")
		_time_manager = time_mgrs[0] if not time_mgrs.is_empty() else null
	if _time_manager != null and _time_manager.has_method("set_weather_factors"):
		_time_manager.call("set_weather_factors", overcast_factor, rain_intensity)

	# 3. Update world environment (fog & ambient light)
	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		# Rain and overcast increase fog density and turn haze cool blue-grey
		var base_density := 0.0011
		var max_density := 0.0055 if rain_intensity > 0.5 else 0.0028
		env.fog_density = lerpf(base_density, max_density, maxf(overcast_factor, rain_intensity))
		var clear_fog := Color("7d8b94")
		var rain_fog := Color("4a545e")
		env.fog_light_color = clear_fog.lerp(rain_fog, maxf(overcast_factor, rain_intensity))


func _trigger_thunder() -> void:
	# Distant lightning flash: momentary spike in environment ambient energy
	if world_env != null and world_env.environment != null:
		var env := world_env.environment
		var orig_energy := env.ambient_light_energy
		var tween := create_tween()
		tween.tween_property(env, "ambient_light_energy", orig_energy + 0.8, 0.08)
		tween.tween_property(env, "ambient_light_energy", orig_energy, 0.25)

	# Sound via AudioDirector
	var audio = get_node_or_null("/root/AudioDirector")
	if audio != null and audio.has_method("play_thunder"):
		audio.call("play_thunder")
