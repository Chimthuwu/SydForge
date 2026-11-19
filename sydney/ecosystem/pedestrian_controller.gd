class_name PedestrianController
extends CharacterBody3D

const GoreEffectsScript := preload("res://scripts/gore_effects.gd")

## Autonomous Sydney pedestrian navigating footpaths, plazas, and pedestrian crossings.
## Features procedural appearance (skin, shirt, trousers/skirt, hair), walking locomotion,
## and path-following with collision avoidance.

var graph_nodes: Dictionary = {}
var current_node_id: int = -1
var target_node_id: int = -1

var walk_speed: float = 1.4 # m/s (standard walking pace)
var is_waiting: bool = false
var wait_timer: float = 0.0

# Visual parts
var body_root: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var walk_anim_time: float = 0.0
var health: float = 100.0
var is_dead: bool = false
var _skin_color: Color = Color("d9a079")
var _shirt_color: Color = Color("3d4850")
var _pant_color: Color = Color("263238")

## Distance LOD for the 50 peaceful walkers; see traffic controller.
var _player: Node3D
var _sim_accum: float = 0.0

func _ready() -> void:
	add_to_group("pedestrians")
	_build_visuals()

func setup(start_id: int, nodes_dict: Dictionary) -> void:
	graph_nodes = nodes_dict
	current_node_id = start_id
	if current_node_id in graph_nodes:
		var n: Dictionary = graph_nodes[current_node_id]
		global_position = Vector3(float(n["x"]), 0.15, float(n["z"]))
	_pick_next_target()

func _pick_next_target() -> void:
	if not (current_node_id in graph_nodes):
		return
	var n: Dictionary = graph_nodes[current_node_id]
	var neighbors: Array = n.get("neighbors", [])
	if neighbors.is_empty():
		return
	target_node_id = neighbors[randi() % neighbors.size()]

func _build_visuals() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	
	# Height variance (1.6m to 1.88m)
	var scale_y := randf_range(0.92, 1.08)
	var scale_xz := randf_range(0.95, 1.05)
	body_root.scale = Vector3(scale_xz, scale_y, scale_xz)
	
	# Colour variation
	var skin_tones := [Color("f5d0b5"), Color("e0ac69"), Color("8d5524"), Color("c68642"), Color("ffdbac")]
	var shirt_colors := [
		Color("1e88e5"), Color("e53935"), Color("43a047"), Color("fdd835"),
		Color("fb8c00"), Color("ffffff"), Color("212121"), Color("8e24aa")
	]
	var pant_colors := [Color("263238"), Color("37474f"), Color("1a237e"), Color("424242"), Color("b0bec5")]
	var hair_colors := [Color("1a1a1a"), Color("4a2c11"), Color("b5814c"), Color("d4af37"), Color("808080")]
	
	var skin_col: Color = skin_tones[randi() % skin_tones.size()]
	var shirt_col: Color = shirt_colors[randi() % shirt_colors.size()]
	var pant_col: Color = pant_colors[randi() % pant_colors.size()]
	var hair_col: Color = hair_colors[randi() % hair_colors.size()]
	_skin_color = skin_col
	_shirt_color = shirt_col
	_pant_color = pant_col
	
	# Torso
	Art.box(body_root, Vector3(0, 1.05, 0), Vector3(0.42, 0.55, 0.22), shirt_col)
	# Neck & Head
	Art.cylinder(body_root, Vector3(0, 1.38, 0), 0.08, 0.12, skin_col)
	Art.box(body_root, Vector3(0, 1.55, 0), Vector3(0.24, 0.26, 0.24), skin_col)
	# Hair
	Art.box(body_root, Vector3(0, 1.68, 0), Vector3(0.26, 0.12, 0.26), hair_col)
	
	# Legs
	left_leg = Node3D.new()
	left_leg.position = Vector3(-0.11, 0.8, 0)
	body_root.add_child(left_leg)
	Art.box(left_leg, Vector3(0, -0.4, 0), Vector3(0.16, 0.8, 0.18), pant_col)
	Art.box(left_leg, Vector3(0, -0.78, 0.04), Vector3(0.17, 0.12, 0.24), Color("111111")) # Shoes
	
	right_leg = Node3D.new()
	right_leg.position = Vector3(0.11, 0.8, 0)
	body_root.add_child(right_leg)
	Art.box(right_leg, Vector3(0, -0.4, 0), Vector3(0.16, 0.8, 0.18), pant_col)
	Art.box(right_leg, Vector3(0, -0.78, 0.04), Vector3(0.17, 0.12, 0.24), Color("111111"))
	
	# Arms
	left_arm = Node3D.new()
	left_arm.position = Vector3(-0.25, 1.25, 0)
	body_root.add_child(left_arm)
	Art.box(left_arm, Vector3(0, -0.3, 0), Vector3(0.12, 0.58, 0.14), shirt_col)
	Art.box(left_arm, Vector3(0, -0.62, 0), Vector3(0.10, 0.12, 0.12), skin_col) # Hand
	
	right_arm = Node3D.new()
	right_arm.position = Vector3(0.25, 1.25, 0)
	body_root.add_child(right_arm)
	Art.box(right_arm, Vector3(0, -0.3, 0), Vector3(0.12, 0.58, 0.14), shirt_col)
	Art.box(right_arm, Vector3(0, -0.62, 0), Vector3(0.10, 0.12, 0.12), skin_col)
	
	# Collision capsule
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	add_child(col)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var step := delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null:
		var interval := 0.0
		var distance := global_position.distance_to(_player.global_position)
		if distance > 70.0:
			interval = 1.0 / 15.0
		elif distance > 30.0:
			interval = 1.0 / 30.0
		if interval > 0.0:
			_sim_accum += delta
			if _sim_accum < interval:
				return
			step = _sim_accum
			_sim_accum = 0.0
	if is_waiting:
		wait_timer -= step
		if wait_timer <= 0.0:
			is_waiting = false
			_pick_next_target()
		_animate_walking(0.0, step)
		return
	
	if not (target_node_id in graph_nodes):
		_pick_next_target()
		return
	
	var target_data: Dictionary = graph_nodes[target_node_id]
	var target_pos := Vector3(float(target_data["x"]), global_position.y, float(target_data["z"]))
	var diff := target_pos - global_position
	diff.y = 0.0
	var dist := diff.length()
	
	if dist < 1.0:
		current_node_id = target_node_id
		# Occasionally wait at intersections/crossings (20% chance)
		if randf() < 0.2:
			is_waiting = true
			wait_timer = randf_range(2.0, 5.0)
		else:
			_pick_next_target()
		return
	
	var fwd := diff.normalized()
	var step_scale := step / maxf(get_physics_process_delta_time(), 0.0001)
	velocity.x = fwd.x * walk_speed * step_scale
	velocity.z = fwd.z * walk_speed * step_scale
	velocity.y -= 9.8 * step
	
	rotation.y = atan2(-fwd.x, -fwd.z)
	move_and_slide()
	
	_animate_walking(walk_speed, step)

func take_damage_at(
	amount: float,
	impact_position: Vector3,
	impact_intensity: float = 1.0,
	shot_direction: Vector3 = Vector3.FORWARD
) -> void:
	if is_dead:
		return
	health = maxf(0.0,health-amount)
	GoreEffectsScript.spawn_hit_spray(get_parent(),impact_position,impact_intensity,shot_direction)
	if health > 0.0:
		return
	_die(impact_intensity * shot_direction.normalized() * 3.0)


func hit_by_vehicle(impact_speed: float, source: Node3D = null) -> bool:
	if is_dead or impact_speed < 2.0:
		return false
	var vehicle_velocity := Vector3.ZERO
	if source != null and "velocity" in source:
		vehicle_velocity = source.get("velocity")
	if vehicle_velocity.length() < 2.0:
		vehicle_velocity = Vector3.FORWARD * impact_speed
	_die(vehicle_velocity * clampf(impact_speed / 12.0, 0.8, 2.4))
	return true


func _die(launch_velocity: Vector3) -> void:
	if is_dead:
		return
	is_dead = true
	set_physics_process(false)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	for shape: CollisionShape3D in find_children("*","CollisionShape3D",true,false):
		shape.set_deferred("disabled",true)
	if body_root != null:
		body_root.visible = false
	GoreEffectsScript.spawn_body_destruction(
		get_parent(), global_position, launch_velocity, _skin_color, _shirt_color
	)
	var cleanup := get_tree().create_timer(1.0)
	cleanup.timeout.connect(queue_free)

func _animate_walking(spd: float, delta: float) -> void:
	if spd > 0.1:
		walk_anim_time += delta * spd * 4.5
		var angle := sin(walk_anim_time) * 0.45
		if left_leg != null:
			left_leg.rotation.x = angle
		if right_leg != null:
			right_leg.rotation.x = -angle
		if left_arm != null:
			left_arm.rotation.x = -angle * 0.8
		if right_arm != null:
			right_arm.rotation.x = angle * 0.8
	else:
		if left_leg != null:
			left_leg.rotation.x = move_toward(left_leg.rotation.x, 0.0, delta * 3.0)
		if right_leg != null:
			right_leg.rotation.x = move_toward(right_leg.rotation.x, 0.0, delta * 3.0)
		if left_arm != null:
			left_arm.rotation.x = move_toward(left_arm.rotation.x, 0.0, delta * 3.0)
		if right_arm != null:
			right_arm.rotation.x = move_toward(right_arm.rotation.x, 0.0, delta * 3.0)
