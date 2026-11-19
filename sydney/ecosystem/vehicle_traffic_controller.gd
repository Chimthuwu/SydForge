class_name VehicleTrafficController
extends CharacterBody3D

## Individual autonomous vehicle controller following road network splines/waypoints.
## Handles acceleration, lane adherence, stopping behind other vehicles or at red signals,
## and night headlights/taillights activation.

@export var vehicle_class: int = VehicleVisualBuilder.VehicleClass.SEDAN

var road_points: Array[Vector3] = []
var current_point_idx: int = 0
var current_speed: float = 0.0
var target_speed: float = 12.0
var max_speed: float = 15.0
var accel_rate: float = 8.0
var brake_rate: float = 18.0
var turn_speed: float = 2.5

var lane_offset: float = 0.0
var road_forward_dir: int = 1 # 1 = forward, -1 = reverse along points

# Visual components
var wheels: Array[MeshInstance3D] = []
var headlights: Array[MeshInstance3D] = []
var taillights: Array[MeshInstance3D] = []
var spot_light: SpotLight3D

var is_braking: bool = false
var is_night: bool = false
var collision_shape: CollisionShape3D
var driver: BoomPlayer
var vehicle_name: String = "Sydney traffic"
var health: float = 100.0
var max_health: float = 100.0
var vehicle_length: float = 4.5
var vehicle_width: float = 1.9
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

func _ready() -> void:
	add_to_group("traffic_vehicles")
	_setup_vehicle()

func setup_route(points: Array[Vector3], offset: float, forward: bool) -> void:
	road_points = points
	lane_offset = offset
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
	# Build visuals
	var palette := [
		Color("ef5350"), Color("42a5f5"), Color("66bb6a"), Color("ffa726"),
		Color("ab47bc"), Color("eceff1"), Color("263238"), Color("78909c")
	]
	var paint_col: Color = palette[randi() % palette.size()]
	if vehicle_class == VehicleVisualBuilder.VehicleClass.TAXI:
		paint_col = Color("ffd600")
	elif vehicle_class == VehicleVisualBuilder.VehicleClass.BUS:
		paint_col = Color("1565c0")
	elif vehicle_class == VehicleVisualBuilder.VehicleClass.GARBAGE_TRUCK:
		paint_col = Color("2e7d32")

	var build_data := VehicleVisualBuilder.build_vehicle_visuals(self, vehicle_class, paint_col)
	wheels = build_data["wheels"]
	headlights = build_data["headlights"]
	taillights = build_data["taillights"]
	var specs: Dictionary = build_data["specs"]
	vehicle_name = str(specs.get("name","Sydney traffic"))
	vehicle_length = float(specs.get("length",4.5))
	vehicle_width = float(specs.get("width",1.9))
	
	max_speed = specs.get("max_speed", 16.0) * 0.45 # Scale down to sensible city speeds (30-60 km/h)
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
	
	# Clearance raycast
	clearance_ray = RayCast3D.new()
	clearance_ray.position = Vector3(0, 0.6, -specs["length"] * 0.5)
	clearance_ray.target_position = Vector3(0, 0, -8.0) # Look 8m ahead
	clearance_ray.collision_mask = 1 # Collide with vehicles and player
	add_child(clearance_ray)
	
	# Spot light for night driving
	spot_light = SpotLight3D.new()
	spot_light.position = Vector3(0, 0.7, -specs["length"] * 0.5)
	spot_light.rotation_degrees = Vector3(-5, 0, 0)
	spot_light.spot_range = 28.0
	spot_light.spot_angle = 35.0
	spot_light.light_color = Color("fff5dd")
	spot_light.light_energy = 0.0
	spot_light.shadow_enabled = false
	add_child(spot_light)
	
	# Hook into time manager if available
	var time_mgrs := get_tree().get_nodes_in_group("time_managers")
	if not time_mgrs.is_empty():
		var tm = time_mgrs[0]
		is_night = tm.is_night
		tm.night_mode_changed.connect(_on_night_mode_changed)
		_update_night_lights(is_night)

func _on_night_mode_changed(night: bool) -> void:
	is_night = night
	_update_night_lights(night)

func _update_night_lights(night: bool) -> void:
	if spot_light != null:
		spot_light.light_energy = 1.4 if night else 0.0
	
	for hl in headlights:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("fff8d6")
		mat.emission_enabled = night
		mat.emission = Color("fff8d6")
		mat.emission_energy_multiplier = 2.0 if night else 0.0
		hl.material_override = mat
	
	_update_brake_lights()

func _update_brake_lights() -> void:
	for tl in taillights:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("cc1111")
		mat.emission_enabled = true
		mat.emission = Color("ff2222")
		# Bright if braking, dim if night driving, off if daytime non-braking
		if is_braking:
			mat.emission_energy_multiplier = 3.5
		elif is_night:
			mat.emission_energy_multiplier = 0.8
		else:
			mat.emission_enabled = false
		tl.material_override = mat

func _physics_process(delta: float) -> void:
	if road_points.is_empty():
		return
	if driver != null:
		_drive_player_controlled(delta)
		return
	
	# 1. Obstacle clearance check
	var obstructed := false
	if clearance_ray != null and clearance_ray.is_colliding():
		obstructed = true
	
	# 2. Target waypoint
	var target_pt := _get_target_waypoint(current_point_idx)
	var to_target := target_pt - global_position
	to_target.y = 0.0
	var dist_to_target := to_target.length()
	
	# Switch to next point when within threshold
	if dist_to_target < 3.5:
		current_point_idx += road_forward_dir
		if current_point_idx < 0 or current_point_idx >= road_points.size():
			# Loop or reverse direction
			road_forward_dir = -road_forward_dir
			current_point_idx += road_forward_dir * 2
			current_point_idx = clampi(current_point_idx, 0, road_points.size() - 1)
		target_pt = _get_target_waypoint(current_point_idx)
		to_target = (target_pt - global_position)
		to_target.y = 0.0
	
	# 3. Steering
	if to_target.length_squared() > 0.01:
		var target_fwd := to_target.normalized()
		var target_yaw := atan2(-target_fwd.x, -target_fwd.z)
		var current_yaw := rotation.y
		var diff := wrapf(target_yaw - current_yaw, -PI, PI)
		rotation.y += clampf(diff, -turn_speed * delta, turn_speed * delta)
	
	# 4. Acceleration / Braking
	if obstructed:
		is_braking = true
		current_speed = move_toward(current_speed, 0.0, brake_rate * delta)
	else:
		is_braking = false
		current_speed = move_toward(current_speed, target_speed, accel_rate * delta)
	
	_update_brake_lights()
	
	# 5. Movement
	var fwd_dir := -global_transform.basis.z
	velocity = fwd_dir * current_speed
	velocity.y -= 9.8 * delta # gravity
	move_and_slide()
	
	# 6. Spin wheels
	var spin := (current_speed / 0.35) * delta
	for w in wheels:
		w.rotate_x(spin)

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
	return true

func exit_vehicle() -> bool:
	if driver == null:
		return false
	if absf(current_speed) > 3.0:
		driver.world.message = "Slow down to exit"
		return false
	for offset in [
		Vector3(vehicle_width * 0.5 + 0.8,0.2,0),
		Vector3(-vehicle_width * 0.5 - 0.8,0.2,0),
		Vector3(0,0.2,vehicle_length * 0.5 + 1.0)
	]:
		var point: Vector3 = global_position + global_basis * offset
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.9
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY,point + Vector3.UP)
		query.exclude = [get_rid(),driver.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(query).is_empty():
			var old_driver := driver
			_force_release_driver(old_driver,point)
			return true
	driver.world.message = "Exit blocked · move to an open area"
	return false

func force_release_driver(player: BoomPlayer) -> void:
	_force_release_driver(player,player.spawn)

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
	var axis := Input.get_axis("back","forward")
	var turn := Input.get_axis("left","right")
	is_braking = Input.is_action_pressed("jump")
	if is_braking:
		current_speed = move_toward(current_speed,0.0,brake_rate*delta)
	elif absf(axis) > 0.01:
		var target := max_speed * axis
		current_speed = move_toward(current_speed,target,accel_rate*delta)
	else:
		current_speed = move_toward(current_speed,0.0,4.0*delta)
	rotation.y -= turn * turn_speed * clampf(absf(current_speed) / 8.0,0.0,1.0) * delta
	_update_brake_lights()
	velocity = -global_transform.basis.z * current_speed
	velocity.y -= 9.8 * delta
	move_and_slide()
	for collision_index in get_slide_collision_count():
		var collider := get_slide_collision(collision_index).get_collider()
		if collider is Node and collider.is_in_group("wildlife") \
		and collider.has_method("hit_by_vehicle"):
			collider.call("hit_by_vehicle",absf(current_speed),self)
	for wheel in wheels:
		wheel.rotate_x((current_speed / 0.35) * delta)

func _get_target_waypoint(idx: int) -> Vector3:
	idx = clampi(idx, 0, road_points.size() - 1)
	var pt := road_points[idx]
	# Apply lateral lane offset
	if road_points.size() > 1:
		var next_idx := clampi(idx + 1, 0, road_points.size() - 1)
		var prev_idx := clampi(idx - 1, 0, road_points.size() - 1)
		var tangent := (road_points[next_idx] - road_points[prev_idx]).normalized()
		var normal := Vector3(-tangent.z, 0, tangent.x) # lateral right
		pt += normal * lane_offset
	return pt
