class_name PoliceCar
extends CharacterBody3D

## Police interceptor with proportionate, believable pursuit behavior. Pursues and
## pressures at higher wanted levels but uses reaction delays, line-of-sight checks,
## imperfect aim, and escapable tracking instead of superhuman awareness.

static var _active_siren_voices: int = 0

var target: Node3D
var speed: float = 0.0
var max_speed: float = 19.0
var accel: float = 8.5
var turn_rate: float = 1.55
var health: float = 100.0
var fire_cooldown: float = 0.0
var light_bar: Node3D
var _red: OmniLight3D
var _blue: OmniLight3D
var _siren_phase: float = 0.0
var _siren_audio: AudioStreamPlayer3D
var _siren_voice_active: bool = false

var _reaction_delay: float = 0.0
var _lost_sight_time: float = 0.0
var _last_seen_pos: Vector3 = Vector3.ZERO
var _has_last_seen: bool = false
var _search_time: float = 0.0
var _decision_timer: float = 0.0
var _aim_error: float = 0.0
var _perceived_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("police")
	add_to_group("police_vehicles")
	_build_visuals()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.1, 1.4, 4.6)
	shape.shape = box
	shape.position.y = 0.8
	add_child(shape)
	floor_snap_length = 0.7
	light_bar = Node3D.new()
	light_bar.name = "LightBar"
	light_bar.position = Vector3(0.0, 1.85, 0.0)
	add_child(light_bar)
	_red = _lamp("RedLight", Color("ff2a2a"), -0.45)
	_blue = _lamp("BlueLight", Color("2a6cff"), 0.45)
	_setup_siren_audio()
	_reaction_delay = randf_range(0.35, 0.75)
	_decision_timer = randf_range(0.15, 0.35)
	_aim_error = randf_range(-0.18, 0.18)


func _lamp(node_name: String, color: Color, x: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = Vector3(x, 0.0, 0.0)
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = 18.0
	light.shadow_enabled = false
	light_bar.add_child(light)
	return light


func _build_visuals() -> void:
	var body := Node3D.new()
	body.name = "PoliceBody"
	add_child(body)
	Art.tapered_box(body, Vector3(0, 0.8, 0), Vector3(2.0, 0.9, 4.6), Vector2(1.8, 4.2), Color("ecece6"))
	Art.box(body, Vector3(0, 0.9, 0.1), Vector3(2.02, 0.32, 2.1), Color("1a1d22"))
	Art.box(body, Vector3(0, 1.15, 0.2), Vector3(1.8, 0.55, 2.0), Color("2a3038"))
	Art.box(body, Vector3(0, 1.55, 0.0), Vector3(0.6, 0.12, 0.3), Color("101318"))
	for side in [-1.0, 1.0]:
		for z in [-1.4, 1.4]:
			var wheel := Art.cylinder(body, Vector3(side * 1.02, 0.42, z), 0.42, 0.26, Color("15171a"))
			wheel.rotation.z = PI * 0.5


func set_pursuit_target(player: Node3D) -> void:
	target = player


func _exit_tree() -> void:
	if _siren_voice_active:
		_active_siren_voices = maxi(0, _active_siren_voices - 1)
		_siren_voice_active = false


func _setup_siren_audio() -> void:
	_siren_audio = AudioStreamPlayer3D.new()
	_siren_audio.name = "PursuitSiren"
	_siren_audio.bus = "Vehicles"
	_siren_audio.unit_size = 14.0
	_siren_audio.max_distance = 85.0
	_siren_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_siren_audio.volume_db = -10.0
	_siren_audio.max_db = -3.0

	# Synthesized two-tone wail kept conservative so multiple units do not stack
	# into an overwhelming wall of sound. Playback is capped globally.
	const SAMPLE_RATE := 22050
	const DURATION := 1.6
	var count := int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var freq := 620.0 if fmod(t, 0.8) < 0.4 else 860.0
		var sample_val := sin(TAU * freq * t) * 0.22
		var int_val := int(clampf(sample_val, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, int_val)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	_siren_audio.stream = stream
	add_child(_siren_audio)
	_update_siren_audio(true)


func _update_siren_audio(force: bool = false) -> void:
	if _siren_audio == null or not is_instance_valid(_siren_audio):
		return
	var stars := _wanted_stars()
	var listener := get_viewport().get_camera_3d() if get_viewport() != null else null
	var distance := 0.0
	if listener != null:
		distance = global_position.distance_to(listener.global_position)
	# Audible when actively engaged nearby; distant/occasional presence stays subdued.
	var want := stars > 0 and distance < 120.0 and _lost_sight_time < 10.0
	if not want and not force and not _siren_audio.playing:
		return
	if want:
		if not _siren_audio.playing:
			if _active_siren_voices >= 3 and not _siren_voice_active:
				return
			if not _siren_voice_active:
				_active_siren_voices += 1
				_siren_voice_active = true
			_siren_audio.play()
		# Fade with distance so sirens are atmospheric when far away.
		var dist_db := clampf((distance - 12.0) * 0.11, 0.0, 18.0)
		_siren_audio.volume_db = -10.0 - dist_db
		_siren_audio.pitch_scale = 1.0
	else:
		if _siren_audio.playing:
			_siren_audio.stop()
		if _siren_voice_active:
			_active_siren_voices = maxi(0, _active_siren_voices - 1)
			_siren_voice_active = false


func _physics_process(dt: float) -> void:
	_siren_phase += dt * 6.2
	if _red != null:
		_red.light_energy = 2.6 if sin(_siren_phase) > 0.0 else 0.15
	if _blue != null:
		_blue.light_energy = 2.6 if sin(_siren_phase) <= 0.0 else 0.15
	fire_cooldown = maxf(0.0, fire_cooldown - dt)
	_reaction_delay = maxf(0.0, _reaction_delay - dt)
	_decision_timer -= dt
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(0.22, 0.45)
		_aim_error = randf_range(-0.22, 0.22)
	# Always apply gravity/slide first so a police car can never hover when its
	# target is missing or being freed.
	velocity.y -= 24.0 * dt
	move_and_slide()
	_update_siren_audio()
	if target == null or not is_instance_valid(target):
		speed = move_toward(speed, 0.0, accel * dt)
		velocity.x = move_toward(velocity.x, 0.0, accel * dt)
		velocity.z = move_toward(velocity.z, 0.0, accel * dt)
		return

	var stars := _wanted_stars()
	var target_point := _current_target_point()
	var to_target := target_point - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var has_los := _can_see_target(distance)
	if has_los:
		_lost_sight_time = 0.0
		_last_seen_pos = target_point
		_has_last_seen = true
		_search_time = 8.0
		_perceived_target = target_point
	else:
		_lost_sight_time += dt

	var pursuit_point := _perceived_target
	if not has_los:
		if _has_last_seen and _lost_sight_time < 8.0:
			pursuit_point = _last_seen_pos
		else:
			# Lost track: disengage pursuit behavior.
			speed = move_toward(speed, 0.0, accel * 1.2 * dt)
			velocity.x = move_toward(velocity.x, -sin(rotation.y) * speed, accel * dt)
			velocity.z = move_toward(velocity.z, -cos(rotation.y) * speed, accel * dt)
			return

	if _reaction_delay > 0.0:
		# Human reaction delay: keep current heading/speed briefly.
		speed = move_toward(speed, speed * 0.98, accel * dt)
		velocity.x = -sin(rotation.y) * speed
		velocity.z = -cos(rotation.y) * speed
		return

	var to_pursuit := pursuit_point - global_position
	to_pursuit.y = 0.0
	if to_pursuit.length() < 0.5:
		return
	var desired_yaw := atan2(-to_pursuit.x, -to_pursuit.z) + _aim_error * 0.15
	var diff := wrapf(desired_yaw - rotation.y, -PI, PI)
	rotation.y += clampf(diff, -turn_rate * dt, turn_rate * dt)

	var star_speed_cap := 14.0 + float(clampi(stars, 1, 5)) * 1.6
	var speed_cap := minf(max_speed, star_speed_cap)
	var desired_speed := speed_cap
	if distance < 10.0:
		desired_speed = speed_cap * 0.45
	elif distance < 18.0:
		desired_speed = speed_cap * 0.7
	if not has_los:
		desired_speed = minf(desired_speed, speed_cap * 0.55)
	# Avoid unrealistic bursts and keep pursuits escapable.
	speed = move_toward(speed, desired_speed, accel * dt)
	velocity.x = -sin(rotation.y) * speed
	velocity.z = -cos(rotation.y) * speed

	# Ram/contact pressure when close to the player's vehicle, proportionate.
	var player_vehicle = target.get("vehicle") if "vehicle" in target else null
	if player_vehicle is Node3D and is_instance_valid(player_vehicle):
		if global_position.distance_to(player_vehicle.global_position) < 3.4 and speed > 5.0:
			if player_vehicle.has_method("take_damage"):
				player_vehicle.take_damage((3.0 + float(stars) * 0.8) * dt)

	# Fire only in serious incidents, at close range, with LOS and imperfect aim.
	if stars >= 4 and has_los and distance < 13.0 and fire_cooldown <= 0.0:
		_attempt_shot(distance, stars)


func _current_target_point() -> Vector3:
	var vehicle = target.get("vehicle") if "vehicle" in target else null
	if vehicle is Node3D and is_instance_valid(vehicle):
		return vehicle.global_position + Vector3.UP * 0.8
	return target.global_position + Vector3.UP * 1.0


func _can_see_target(distance: float) -> bool:
	if distance > 120.0:
		return false
	# Distant "awareness" is imperfect; close range is easier to maintain.
	if distance > 45.0 and randf() < 0.02:
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return distance < 40.0
	var from := global_position + Vector3.UP * 1.4
	var to := _current_target_point()
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array = [get_rid()]
	if target != null:
		exclude.append(target.get_rid())
		var vehicle = target.get("vehicle") if "vehicle" in target else null
		if vehicle is Node3D and is_instance_valid(vehicle):
			exclude.append(vehicle.get_rid())
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_pos: Vector3 = hit.get("position", from)
	return hit_pos.distance_to(to) < 3.5


func _attempt_shot(distance: float, stars: int) -> void:
	# Slower, less frequent fire with clear misses and falloff.
	fire_cooldown = randf_range(1.3, 2.2)
	var hit_chance := 0.38
	if distance > 7.0:
		hit_chance -= (distance - 7.0) * 0.04
	if distance > 10.0:
		hit_chance -= 0.08
	hit_chance -= absf(_aim_error) * 0.25
	hit_chance = clampf(hit_chance - float(5 - stars) * 0.03, 0.08, 0.42)
	if randf() > hit_chance:
		return
	# Damage is proportionate and reduced at range.
	var damage := 3.5
	if distance > 8.0:
		damage = 2.0
	if target != null and target.has_method("take_damage"):
		target.take_damage(damage)


func _wanted_stars() -> int:
	var wanted := get_tree().get_first_node_in_group("wanted_system")
	return int(wanted.get("stars")) if wanted != null else 0
