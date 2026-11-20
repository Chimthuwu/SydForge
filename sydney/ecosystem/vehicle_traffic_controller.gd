class_name VehicleTrafficController
extends CharacterBody3D

## Individual autonomous vehicle controller following road network splines/waypoints.
## Complies with Australian left-hand traffic, maintains adaptive following distances,
## respects red signals and pedestrian crossings, yields to emergency sirens,
## supports multi-lane lane changing, and handles smooth cornering.

@export var vehicle_class: int = VehicleVisualBuilder.VehicleClass.SEDAN

var road_points: Array[Vector3] = []
var current_point_idx: int = 0
var current_speed: float = 0.0
var target_speed: float = 12.0
var max_speed: float = 15.0
var accel_rate: float = 8.0
var brake_rate: float = 18.0
var turn_speed: float = 2.5

var lane_offset: float = 2.0
var current_lane_offset: float = 2.0
var target_lane_offset: float = 2.0
var road_forward_dir: int = 1 # 1 = forward, -1 = reverse along points

# Visual components
var wheels: Array[MeshInstance3D] = []
var headlights: Array[MeshInstance3D] = []
var taillights: Array[MeshInstance3D] = []
var emergency_light_meshes: Array[MeshInstance3D] = []
var emergency_light_nodes: Array[OmniLight3D] = []
var spot_light: SpotLight3D
var rear_light: OmniLight3D
var headlight_materials: Array[StandardMaterial3D] = []
var taillight_materials: Array[StandardMaterial3D] = []
var emergency_materials: Array[StandardMaterial3D] = []

var is_braking: bool = false
var is_night: bool = false
var is_yielding: bool = false
var lighting_factor: float = 0.0
var _light_distance_timer: float = 0.0
var collision_shape: CollisionShape3D
var engine_audio_system: EngineAudio
var siren_audio: AudioStreamPlayer3D
var _siren_voice_claimed: bool = false
static var _active_siren_voices: int = 0
const MAX_ACTIVE_SIREN_VOICES := 3
var audio_focus: bool = false
var driver: BoomPlayer
var vehicle_name: String = "Sydney traffic"
var health: float = 100.0
var max_health: float = 100.0
var vehicle_length: float = 4.5
var vehicle_width: float = 1.9

# Emergency service properties
var is_emergency_vehicle: bool = false
var is_emergency_responding: bool = false
var _emergency_flash_phase: float = 0.0

# Lane changing & intersection state
var is_turning: bool = false
var blocked_time: float = 0.0
var _can_change_lane: bool = false
var _traffic_manager: Node3D

## Set by the incident manager for responders, and by the world director for
## dangerous-driving reactions. Neither is a teleport: the car keeps following
## its road spline while these states adjust speed and direction choice.
var _destination: Vector3 = Vector3.ZERO
var _has_destination: bool = false
var _threat_position: Vector3 = Vector3.ZERO
var _threat_time: float = 0.0
var _pulled_over: bool = false

var is_player_controlled: bool:
	get:
		return driver != null
var speed: float:
	get:
		return current_speed
	set(value):
		current_speed = value

# Raycast forward clearance check
var clearance_ray: RayCast3D
var clearance_ray_left: RayCast3D
var clearance_ray_right: RayCast3D

## Distance LOD for performance
var _player: Node3D
var _sim_accum: float = 0.0
var _audio_timer: float = 0.0


func _ready() -> void:
	add_to_group("traffic_vehicles")
	_setup_vehicle()


func setup_route(points: Array[Vector3], offset: float, forward: bool) -> void:
	road_points = points
	lane_offset = absf(offset)
	current_lane_offset = lane_offset
	target_lane_offset = lane_offset
	road_forward_dir = 1 if forward else -1
	current_point_idx = 0 if forward else (points.size() - 1)
	
	if not road_points.is_empty():
		var start_pt := _get_target_waypoint(current_point_idx)
		global_position = start_pt
		var next_idx := current_point_idx + road_forward_dir
		if next_idx >= 0 and next_idx < road_points.size():
			var nxt := _get_target_waypoint(next_idx)
			var fwd := (nxt - start_pt).normalized()
			if fwd.length_squared() > 0.001:
				rotation.y = atan2(-fwd.x, -fwd.z)


func _setup_vehicle() -> void:
	is_emergency_vehicle = (
		vehicle_class == VehicleVisualBuilder.VehicleClass.POLICE
		or vehicle_class == VehicleVisualBuilder.VehicleClass.AMBULANCE
		or vehicle_class == VehicleVisualBuilder.VehicleClass.FIRE_TRUCK
	)
	if is_emergency_vehicle and randf() < 0.35:
		is_emergency_responding = true

	# Restrained real-world Sydney traffic palette
	var palette := [
		Color("8a3b35"), Color("345064"), Color("4c5a4c"), Color("9a7a3e"),
		Color("59485f"), Color("c4c4be"), Color("292d31"), Color("69737a")
	]
	var paint_col: Color = palette[randi() % palette.size()]
	if vehicle_class == VehicleVisualBuilder.VehicleClass.TAXI:
		paint_col = Color("d8a21e")
	elif vehicle_class == VehicleVisualBuilder.VehicleClass.BUS:
		paint_col = Color("24527c")
	elif vehicle_class == VehicleVisualBuilder.VehicleClass.GARBAGE_TRUCK:
		paint_col = Color("2e7d32")

	var build_data := VehicleVisualBuilder.build_vehicle_visuals(self, vehicle_class, paint_col)
	wheels = build_data["wheels"]
	headlights = build_data["headlights"]
	taillights = build_data["taillights"]
	if build_data.has("emergency_lights"):
		emergency_light_meshes = build_data["emergency_lights"]
	if build_data.has("emergency_light_nodes"):
		emergency_light_nodes = build_data["emergency_light_nodes"]

	var specs: Dictionary = build_data["specs"]
	vehicle_name = str(specs.get("name", "Sydney traffic"))
	vehicle_length = float(specs.get("length", 4.5))
	vehicle_width = float(specs.get("width", 1.9))
	
	max_speed = specs.get("max_speed", 16.0) * 0.45
	if is_emergency_responding:
		max_speed *= 1.4
	target_speed = max_speed
	accel_rate = specs.get("accel", 10.0) * 0.7
	turn_speed = specs.get("turn", 2.2)
	
	# Collision shape
	collision_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(specs["width"], specs["height"], specs["length"])
	collision_shape.shape = box
	collision_shape.position.y = specs["height"] * 0.5
	add_child(collision_shape)
	
	# Forward clearance raycasts (center, left shoulder, right shoulder)
	clearance_ray = RayCast3D.new()
	clearance_ray.position = Vector3(0, 0.6, -specs["length"] * 0.5)
	clearance_ray.target_position = Vector3(0, 0, -11.0) # 11m ahead
	clearance_ray.collision_mask = 1
	add_child(clearance_ray)

	clearance_ray_left = RayCast3D.new()
	clearance_ray_left.position = Vector3(-specs["width"] * 0.35, 0.6, -specs["length"] * 0.5)
	clearance_ray_left.target_position = Vector3(0, 0, -9.0)
	clearance_ray_left.collision_mask = 1
	add_child(clearance_ray_left)

	clearance_ray_right = RayCast3D.new()
	clearance_ray_right.position = Vector3(specs["width"] * 0.35, 0.6, -specs["length"] * 0.5)
	clearance_ray_right.target_position = Vector3(0, 0, -9.0)
	clearance_ray_right.collision_mask = 1
	add_child(clearance_ray_right)

	# Night driving headlights & tail lights
	spot_light = SpotLight3D.new()
	spot_light.position = Vector3(0, 0.7, -specs["length"] * 0.5)
	spot_light.rotation_degrees = Vector3(-5, 0, 0)
	spot_light.spot_range = 28.0
	spot_light.spot_angle = 52.0
	spot_light.light_color = Color("fff5dd")
	spot_light.light_energy = 0.0
	spot_light.shadow_enabled = false
	add_child(spot_light)

	rear_light = OmniLight3D.new()
	rear_light.name = "RearLightGlow"
	rear_light.position = Vector3(0.0, 0.72, specs["length"] * 0.5)
	rear_light.omni_range = 5.0
	rear_light.light_color = Color("ff2934")
	rear_light.light_energy = 0.0
	rear_light.shadow_enabled = false
	add_child(rear_light)

	_create_lamp_materials()

	# Engine audio
	engine_audio_system = EngineAudio.new()
	engine_audio_system.name = "EngineAudioSystem"
	engine_audio_system.profile_id = EngineAudio.profile_for_class(vehicle_class)
	engine_audio_system.ai_mode = true
	engine_audio_system.set_audible(false)
	add_child(engine_audio_system)

	# 3D Siren for emergency vehicles
	if is_emergency_vehicle:
		_setup_siren_audio()

	# Day/Night connection
	var time_mgrs := get_tree().get_nodes_in_group("time_managers")
	if not time_mgrs.is_empty():
		var tm = time_mgrs[0]
		is_night = tm.is_night
		lighting_factor = float(tm.get("lighting_factor"))
		tm.night_mode_changed.connect(_on_night_mode_changed)
		tm.lighting_factor_changed.connect(_on_lighting_factor_changed)
		_update_night_lights(lighting_factor)


func _setup_siren_audio() -> void:
	siren_audio = AudioStreamPlayer3D.new()
	siren_audio.name = "EmergencySiren"
	siren_audio.bus = "Vehicles"
	# Quieter, more distance-sensitive siren: audible nearby, atmospheric at range.
	siren_audio.unit_size = 16.0
	siren_audio.max_distance = 75.0
	siren_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	siren_audio.volume_db = -12.0
	siren_audio.max_db = -4.0
	
	# Synthesize authentic Australian two-tone siren at a conservative level to
	# reduce harshness and prevent overlapping responders from dominating the mix.
	const SAMPLE_RATE := 22050
	const DURATION := 1.6
	var count := int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase_offset := randf() # desynchronise phase across vehicles
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var tt := t + phase_offset
		var freq := 620.0 if fmod(tt, 0.8) < 0.4 else 860.0 # Two-tone hi-lo wail
		var sample_val := sin(TAU * freq * t) * 0.16
		var int_val := int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, int_val)
	
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	siren_audio.stream = stream
	add_child(siren_audio)
	
	if is_emergency_responding:
		_try_start_siren()


func set_emergency_responding(active: bool) -> void:
	is_emergency_responding = active
	if is_emergency_responding:
		max_speed = 22.0
		target_speed = max_speed
		_try_start_siren()
	else:
		max_speed = 14.0
		target_speed = max_speed
		_stop_siren()
		for light in emergency_light_nodes:
			light.light_energy = 0.0


func _try_start_siren() -> void:
	if siren_audio == null or not is_instance_valid(siren_audio):
		return
	if siren_audio.playing:
		return
	if _active_siren_voices >= MAX_ACTIVE_SIREN_VOICES and not _siren_voice_claimed:
		return
	if not _siren_voice_claimed:
		_active_siren_voices += 1
		_siren_voice_claimed = true
	siren_audio.play()


func _stop_siren() -> void:
	if siren_audio != null and is_instance_valid(siren_audio) and siren_audio.playing:
		siren_audio.stop()
	if _siren_voice_claimed:
		_active_siren_voices = maxi(0, _active_siren_voices - 1)
		_siren_voice_claimed = false


func _exit_tree() -> void:
	_stop_siren()


func _create_lamp_materials() -> void:
	for hl in headlights:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("fff4dc")
		material.emission_enabled = true
		material.emission = Color("fff0cf")
		material.emission_energy_multiplier = 0.0
		hl.material_override = material
		headlight_materials.append(material)
	for tl in taillights:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("a91620")
		material.emission_enabled = true
		material.emission = Color("ff2635")
		material.emission_energy_multiplier = 0.0
		tl.material_override = material
		taillight_materials.append(material)
	for em in emergency_light_meshes:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("ffffff")
		material.emission_enabled = true
		material.emission = Color("0044ff") if em.position.x < 0 else Color("ff1111")
		material.emission_energy_multiplier = 0.0
		em.material_override = material
		emergency_materials.append(material)


func _on_night_mode_changed(night: bool) -> void:
	is_night = night


func _on_lighting_factor_changed(factor: float) -> void:
	lighting_factor = clampf(factor, 0.0, 1.0)
	_update_night_lights(lighting_factor)


func _update_night_lights(factor: float) -> void:
	if spot_light != null:
		spot_light.light_energy = 2.7 * factor
	if rear_light != null:
		rear_light.light_energy = 0.65 * factor
	for material in headlight_materials:
		material.emission_energy_multiplier = 2.4 * factor
	_update_brake_lights()


func _update_brake_lights() -> void:
	for mat in taillight_materials:
		if is_braking:
			mat.emission_energy_multiplier = 3.5
			mat.emission_enabled = true
		elif lighting_factor > 0.01:
			mat.emission_energy_multiplier = 0.8 * lighting_factor
			mat.emission_enabled = true
		else:
			mat.emission_enabled = false


func _update_light_visibility() -> void:
	var player := driver as Node3D
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node3D
	var distance_sq := INF
	if player != null:
		distance_sq = player.global_position.distance_squared_to(global_position)
	var near_player := lighting_factor > 0.01 and distance_sq < 110.0 * 110.0
	if spot_light != null:
		spot_light.visible = near_player
	if rear_light != null:
		rear_light.visible = near_player and distance_sq < 65.0 * 65.0


func set_audio_focus(value: bool) -> void:
	audio_focus = value
	if engine_audio_system != null:
		engine_audio_system.set_audible(value)


func _update_engine_audio(delta: float) -> void:
	if engine_audio_system == null:
		return
	var rpm := EngineAudio.gear_rpm(current_speed, max_speed)
	engine_audio_system.update_audio(delta, current_speed, rpm, 0.0 if is_braking else 1.0, 0.0, false)


func _physics_process(delta: float) -> void:
	_light_distance_timer += delta
	if _light_distance_timer >= 0.5:
		_light_distance_timer = 0.0
		_update_light_visibility()

	# Emergency flashing lights
	if is_emergency_responding:
		_emergency_flash_phase += delta * 12.0
		var flash_toggle := sin(_emergency_flash_phase) > 0.0
		for i in emergency_light_nodes.size():
			var light := emergency_light_nodes[i]
			light.light_energy = 3.8 if ((i % 2 == 0) == flash_toggle) else 0.2
		for i in emergency_materials.size():
			var mat := emergency_materials[i]
			mat.emission_energy_multiplier = 3.5 if ((i % 2 == 0) == flash_toggle) else 0.3

	if driver != null:
		_update_engine_audio(delta)
		_drive_player_controlled(delta)
		return
	else:
		_audio_timer += delta
		if _audio_timer >= 0.1:
			_update_engine_audio(_audio_timer)
			_audio_timer = 0.0

	if road_points.is_empty():
		return

	# Distance LOD
	var step := delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null:
		var distance := global_position.distance_to(_player.global_position)
		var interval := 0.0
		if distance > 90.0:
			interval = 1.0 / 15.0
		elif distance > 40.0:
			interval = 1.0 / 30.0
		if interval > 0.0:
			_sim_accum += delta
			if _sim_accum < interval:
				return
			step = _sim_accum
			_sim_accum = 0.0

	# 1. Yield to approaching emergency vehicles
	_check_emergency_yielding()

	# 2. Obstacle detection & adaptive following distance
	var min_hit_dist := 999.0
	var obstacle_collider: Object = null
	for ray in [clearance_ray, clearance_ray_left, clearance_ray_right]:
		if ray != null and ray.is_colliding():
			var pt: Vector3 = ray.get_collision_point()
			var d := global_position.distance_to(pt)
			if d < min_hit_dist:
				min_hit_dist = d
				obstacle_collider = ray.get_collider()

	# 3. Intersection & traffic light check
	var traffic_signal_stop := _check_traffic_signals_and_intersections()

	# 4. Target waypoint calculation (Australian left-hand traffic)
	var target_pt := _get_target_waypoint(current_point_idx)
	var to_target := target_pt - global_position
	to_target.y = 0.0
	var dist_to_target := to_target.length()
	
	# Check curve / turning angle ahead to slow down for turns
	var curve_slowdown := 1.0
	if current_point_idx + road_forward_dir >= 0 and current_point_idx + road_forward_dir < road_points.size():
		var next_target := _get_target_waypoint(current_point_idx + road_forward_dir)
		var segment1 := (target_pt - global_position).normalized()
		var segment2 := (next_target - target_pt).normalized()
		var bend := segment1.dot(segment2)
		if bend < 0.75: # Noticeable turn
			curve_slowdown = clampf(bend * 0.7 + 0.3, 0.45, 1.0)

	# Switch waypoint when within range
	if dist_to_target < 3.8:
		current_point_idx += road_forward_dir
		if current_point_idx < 0 or current_point_idx >= road_points.size():
			if _has_destination and road_points.size() > 1:
				var end_a := road_points[0].distance_to(_destination)
				var end_b := road_points[road_points.size() - 1].distance_to(_destination)
				road_forward_dir = 1 if end_b < end_a else -1
			else:
				road_forward_dir = -road_forward_dir
			current_point_idx = 0 if road_forward_dir == 1 else road_points.size() - 1
		target_pt = _get_target_waypoint(current_point_idx)
		to_target = (target_pt - global_position)
		to_target.y = 0.0

	# 5. Steering
	if to_target.length_squared() > 0.01:
		var target_fwd := to_target.normalized()
		var target_yaw := atan2(-target_fwd.x, -target_fwd.z)
		var current_yaw := rotation.y
		var diff := wrapf(target_yaw - current_yaw, -PI, PI)
		rotation.y += clampf(diff, -turn_speed * step, turn_speed * step)

	# 6. Adaptive Acceleration / Braking
	var should_stop := traffic_signal_stop
	var desired_speed := max_speed * curve_slowdown

	_threat_time = maxf(0.0, _threat_time - step)
	if _threat_time > 0.0:
		desired_speed = minf(desired_speed, max_speed * 0.5)

	# Pedestrian crossings: ease through zebra approaches even when no signal
	# is installed. This uses the crossing records already indexed by the manager.
	if _is_approaching_crossing():
		desired_speed = minf(desired_speed, max_speed * 0.45)

	# Temporary obstructions (collisions, roadworks) are avoided rather than
	# driven through. A lane change is attempted once before coming to a stop.
	if _traffic_manager != null and _traffic_manager.has_method("is_road_blocked"):
		var look_ahead := global_position + (-global_transform.basis.z) * 9.0
		if bool(_traffic_manager.call("is_road_blocked", look_ahead)):
			desired_speed = 0.0
			if blocked_time <= 0.1:
				_attempt_lane_change()

	if is_yielding:
		desired_speed = 0.0
		should_stop = true
	elif min_hit_dist < 10.0:
		if min_hit_dist < 4.2:
			# Too close: stop completely
			desired_speed = 0.0
			should_stop = true
			blocked_time += step
		else:
			# Smooth following distance headway
			desired_speed = minf(desired_speed, max_speed * ((min_hit_dist - 4.0) / 6.0))
			should_stop = false
			blocked_time += step * 0.5
	else:
		blocked_time = maxf(0.0, blocked_time - step)

	# Lane change when stuck behind slow/stationary vehicle on multi-lane road
	if blocked_time > 2.0 and not is_yielding:
		_attempt_lane_change()
		blocked_time = 0.0

	# Smoothly transition lateral lane offset
	current_lane_offset = move_toward(current_lane_offset, target_lane_offset, step * 1.8)

	if should_stop or desired_speed < current_speed:
		is_braking = true
		current_speed = move_toward(current_speed, desired_speed, brake_rate * step)
	else:
		is_braking = false
		current_speed = move_toward(current_speed, desired_speed, accel_rate * step)

	_update_brake_lights()

	# 7. Physics movement
	var step_scale := step / maxf(get_physics_process_delta_time(), 0.0001)
	var fwd_dir := -global_transform.basis.z
	velocity = fwd_dir * current_speed * step_scale
	velocity.y -= 9.8 * step
	move_and_slide()

	# 8. Spin wheels
	var spin := (current_speed / 0.35) * step
	for w in wheels:
		w.rotate_x(spin)


func _check_emergency_yielding() -> void:
	if is_emergency_vehicle:
		is_yielding = false
		return
	is_yielding = false
	var emergencies := get_tree().get_nodes_in_group("traffic_vehicles")
	for ev: Node in emergencies:
		if ev != self and ev is Node3D and ev.has_method("is_responding_emergency") and ev.call("is_responding_emergency"):
			var ev_node := ev as Node3D
			var d: float = global_position.distance_to(ev_node.global_position)
			if d < 35.0:
				var to_ev: Vector3 = ev_node.global_position - global_position
				if to_ev.length_squared() <= 0.0:
					continue
				is_yielding = true
				target_lane_offset = lane_offset + 0.9 # Shift slightly to curb
				return


func is_responding_emergency() -> bool:
	return is_emergency_vehicle and is_emergency_responding


func set_destination(point: Vector3) -> void:
	_destination = point
	_has_destination = true


## Player-driven dangerous driving: nearby traffic eases off and edges toward
## the kerb instead of swerving unpredictably into the player's path.
func notice_player_threat(point: Vector3) -> void:
	if is_emergency_vehicle:
		return
	_threat_position = point
	_threat_time = 4.0
	target_lane_offset = lane_offset + 0.9



func _is_approaching_crossing() -> bool:
	if _traffic_manager == null:
		_traffic_manager = get_tree().get_first_node_in_group("traffic_managers") as Node3D
	if _traffic_manager == null or not _traffic_manager.has_method("should_slow_for_crossing"):
		return false
	return bool(_traffic_manager.call("should_slow_for_crossing", global_position, -global_transform.basis.z))


func _check_traffic_signals_and_intersections() -> bool:
	if _traffic_manager == null:
		_traffic_manager = get_tree().get_first_node_in_group("traffic_managers") as Node3D
	if _traffic_manager != null and _traffic_manager.has_method("is_signal_red_for_position"):
		var is_red: bool = _traffic_manager.call("is_signal_red_for_position", global_position, -global_transform.basis.z)
		if is_red:
			return true
	return false


func _attempt_lane_change() -> void:
	# Toggle between curb lane and inner lane
	if absf(target_lane_offset - lane_offset) < 0.2:
		target_lane_offset = lane_offset * 0.45 # Shift to inner lane
	else:
		target_lane_offset = lane_offset # Shift back to curb lane


func _get_target_waypoint(idx: int) -> Vector3:
	idx = clampi(idx, 0, road_points.size() - 1)
	var pt := road_points[idx]
	if road_points.size() > 1:
		var next_idx := clampi(idx + 1, 0, road_points.size() - 1)
		var prev_idx := clampi(idx - 1, 0, road_points.size() - 1)
		var tangent := (road_points[next_idx] - road_points[prev_idx]).normalized()
		var normal := Vector3(-tangent.z, 0, tangent.x) # lateral right of tangent
		
		# In Australia, vehicles travel on the LEFT side of the roadway:
		# Forward along points (road_forward_dir = 1): left side is -normal
		# Reverse along points (road_forward_dir = -1): left side is +normal
		var side_dir := -1.0 if road_forward_dir == 1 else 1.0
		pt += normal * (side_dir * absf(current_lane_offset))
	return pt


func enter(player: BoomPlayer) -> bool:
	if driver != null or health <= 0.0:
		return false
	driver = player
	player.vehicle = self
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.world.rig.arm.add_excluded_object(get_rid())
	current_speed = 0.0
	is_braking = false
	if is_emergency_responding:
		_try_start_siren()
		_update_siren_audibility()
	return true


func _update_siren_audibility() -> void:
	if siren_audio == null or not is_instance_valid(siren_audio):
		return
	if not is_emergency_responding:
		return
	var listener := get_viewport().get_camera_3d() if get_viewport() != null else null
	if listener == null:
		return
	var distance := global_position.distance_to(listener.global_position)
	if distance > 95.0:
		# Distant responders remain visual; no need to contribute to the mix.
		_stop_siren()
	elif not siren_audio.playing:
		_try_start_siren()
	if siren_audio.playing:
		# Smooth distance-based attenuation so nearby sirens read clearly but do
		# not dominate, and farther sirens stay atmospheric.
		var dist_db := clampf((distance - 10.0) * 0.14, 0.0, 16.0)
		siren_audio.volume_db = -12.0 - dist_db


func exit_vehicle() -> bool:
	if driver == null:
		return false
	if absf(current_speed) > 3.0:
		driver.world.message = "Slow down to exit"
		return false
	for offset in [
		Vector3(vehicle_width * 0.5 + 0.8, 0.2, 0),
		Vector3(-vehicle_width * 0.5 - 0.8, 0.2, 0),
		Vector3(0, 0.2, vehicle_length * 0.5 + 1.0)
	]:
		var point: Vector3 = global_position + global_basis * offset
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.9
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP)
		query.exclude = [get_rid(), driver.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query).is_empty():
			var old_driver := driver
			_force_release_driver(old_driver, point)
			return true
	driver.world.message = "Exit blocked · move to an open area"
	return false


func force_release_driver(player: BoomPlayer) -> void:
	_force_release_driver(player, player.spawn)


func _force_release_driver(player: BoomPlayer, exit_point: Vector3) -> void:
	if driver != player:
		return
	driver = null
	player.vehicle = null
	player.global_position = exit_point
	player.velocity = Vector3.ZERO
	player.visible = true
	player.collision_layer = 1
	player.collision_mask = 1
	player.world.rig.arm.remove_excluded_object(get_rid())


func _drive_player_controlled(delta: float) -> void:
	var axis := Input.get_axis("back", "forward")
	var turn := Input.get_axis("left", "right")
	is_braking = Input.is_action_pressed("jump")
	if is_braking:
		current_speed = move_toward(current_speed, 0.0, brake_rate * delta)
	elif absf(axis) > 0.01:
		var target := max_speed * axis
		current_speed = move_toward(current_speed, target, accel_rate * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, 4.0 * delta)
	rotation.y -= turn * turn_speed * clampf(absf(current_speed) / 8.0, 0.0, 1.0) * delta
	_update_brake_lights()
	velocity = -global_transform.basis.z * current_speed
	velocity.y -= 9.8 * delta
	move_and_slide()
	for collision_index in get_slide_collision_count():
		var collider := get_slide_collision(collision_index).get_collider()
		if collider is Node and (
			collider.is_in_group("wildlife") or collider.is_in_group("pedestrians")
		) and collider.has_method("hit_by_vehicle"):
			collider.call("hit_by_vehicle", absf(current_speed), self)
	for wheel in wheels:
		wheel.rotate_x((current_speed / 0.35) * delta)
