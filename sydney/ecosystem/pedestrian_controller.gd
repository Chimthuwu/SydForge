class_name PedestrianController
extends CharacterBody3D

const GoreEffectsScript := preload("res://scripts/gore_effects.gd")

## Autonomous Sydney pedestrian navigating footpaths and crossings.
## Procedural humanoid with articulated limbs, varied appearance, activities and props.

enum Activity { WALK, IDLE, STAND, TALK, PHONE, SMOKE, SIT, WAIT_CROSS, LOITER }

var graph_nodes: Dictionary = {}
var current_node_id: int = -1
var target_node_id: int = -1

var walk_speed: float = 1.4
var is_waiting: bool = false
var wait_timer: float = 0.0

# Visual parts / rig pivots
var body_root: Node3D
var hips: Node3D
var torso: Node3D
var head_node: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_lower_leg: Node3D
var right_lower_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_lower_arm: Node3D
var right_lower_arm: Node3D

var walk_anim_time: float = 0.0
var idle_anim_time: float = 0.0
var health: float = 100.0
var is_dead: bool = false

## World reactivity: short-lived flee/duck-aside state. The routine (activity,
## current/target graph nodes) is restored when the disturbance passes.
var _flee_time: float = 0.0
var _flee_dir: Vector3 = Vector3.ZERO
var _prior_activity: int = Activity.WALK
var _avoid_check: float = 0.0

# Appearance / identity
var _skin_color: Color = Color("d9a079")
var _shirt_color: Color = Color("3d4850")
var _pant_color: Color = Color("263238")
var _hair_color: Color = Color("2a1c12")
var _shoe_color: Color = Color("151515")
var _height_m: float = 1.72
var _outfit := "casual"
var _has_skirt := false
var _has_bag := false
var _has_hat := false
var _archetype := "civilian"
var _district := ""

# Activity / props
var activity: int = Activity.WALK
var _activity_timer: float = 0.0
var _phone: Node3D
var _cigarette: Node3D
var _smoke: Node3D
var _bag: Node3D
var _cup: Node3D
var _gesture_time: float = 0.0

## Distance LOD for the 50 peaceful walkers; see traffic controller.
var _player: Node3D
var _sim_accum: float = 0.0
var _reaction: float = 0.0


func _ready() -> void:
	add_to_group("pedestrians")
	if _archetype == "police":
		add_to_group("police")
	if body_root == null:
		_build_visuals()


func setup(start_id: int, nodes_dict: Dictionary) -> void:
	graph_nodes = nodes_dict
	current_node_id = start_id
	if current_node_id in graph_nodes:
		var n: Dictionary = graph_nodes[current_node_id]
		global_position = Vector3(float(n["x"]), 0.15, float(n["z"]))
	_pick_next_target()


func configure(profile: Dictionary) -> void:
	_archetype = str(profile.get("archetype", _archetype))
	if _archetype == "police" and not is_in_group("police"):
		add_to_group("police")
	_district = str(profile.get("district", _district))
	_outfit = str(profile.get("outfit", _outfit))
	if profile.has("skin"): _skin_color = profile["skin"]
	if profile.has("shirt"): _shirt_color = profile["shirt"]
	if profile.has("pants"): _pant_color = profile["pants"]
	if profile.has("hair"): _hair_color = profile["hair"]
	if profile.has("shoe"): _shoe_color = profile["shoe"]
	if profile.has("height"): _height_m = float(profile["height"])
	if profile.has("walk_speed"): walk_speed = float(profile["walk_speed"])
	_has_skirt = bool(profile.get("skirt", false))
	_has_bag = bool(profile.get("bag", false))
	_has_hat = bool(profile.get("hat", false))
	activity = int(profile.get("activity", Activity.WALK))
	_activity_timer = float(profile.get("activity_time", randf_range(4.0, 12.0)))
	_build_visuals()


func _pick_next_target() -> void:
	if not (current_node_id in graph_nodes):
		return
	var n: Dictionary = graph_nodes[current_node_id]
	var neighbors: Array = n.get("neighbors", [])
	if neighbors.is_empty():
		return
	target_node_id = neighbors[randi() % neighbors.size()]


func _build_visuals() -> void:
	if body_root != null:
		body_root.queue_free()
	body_root = Node3D.new()
	body_root.name = "BodyRoot"
	add_child(body_root)

	_height_m = clampf(_height_m, 1.5, 2.0)
	var s := _height_m / 1.72
	var breadth := randf_range(0.88, 1.14)
	if _archetype in ["police", "worker"]:
		breadth *= 1.04
	body_root.scale = Vector3(s * breadth, s, s * breadth)

	if _skin_color == Color("d9a079") and _archetype == "civilian":
		_choose_default_appearance()
	_build_humanoid()
	_apply_outfit_details()
	_build_props()
	_apply_activity_pose(0.0)


func _choose_default_appearance() -> void:
	# Diverse contemporary Sydney population, including Aboriginal and Torres Strait
	# Islander Australians represented naturally across everyday styles.
	var skin_tones := [
		Color("f6dfcf"), Color("f1d0b5"), Color("e7be9a"), Color("ddb07e"),
		Color("d9a079"), Color("c68642"), Color("b7774f"), Color("a6653f"),
		Color("8d5524"), Color("7a4a2e"), Color("6b3f2a"), Color("5a3524"), Color("4a2c1f"),
	]
	var hair_colors := [
		Color("0f0f10"), Color("1b1410"), Color("2a1c12"), Color("4a2c11"),
		Color("6b4a2b"), Color("8b6a4a"), Color("b5814c"), Color("5a5a5a"), Color("2b2b2b"),
	]
	_skin_color = skin_tones[randi() % skin_tones.size()]
	_hair_color = hair_colors[randi() % hair_colors.size()]
	_shirt_color = Color.from_hsv(randf(), randf_range(0.15, 0.75), randf_range(0.25, 0.95))
	_pant_color = Color.from_hsv(randf(), randf_range(0.05, 0.45), randf_range(0.12, 0.55))
	_shoe_color = [Color("141414"), Color("f0ede6"), Color("6b4a2b"), Color("3a3a3a")][randi() % 4]
	_has_skirt = randf() < 0.18
	_has_bag = randf() < 0.28


func _build_humanoid() -> void:
	hips = Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0.0, 0.93, 0.0)
	body_root.add_child(hips)
	torso = Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0.0, 0.18, 0.0)
	hips.add_child(torso)

	_box(hips, Vector3(0.0, -0.04, 0.0), Vector3(0.34, 0.20, 0.22), _pant_color if not _has_skirt else _shirt_color.darkened(0.05))
	_box(torso, Vector3(0.0, 0.16, 0.0), Vector3(0.30, 0.22, 0.20), _shirt_color)
	_box(torso, Vector3(0.0, 0.38, 0.0), Vector3(0.36, 0.24, 0.22), _shirt_color)
	_box(torso, Vector3(0.0, 0.50, 0.0), Vector3(0.44, 0.10, 0.22), _shirt_color)
	_cyl(torso, Vector3(0.0, 0.60, 0.0), 0.055, 0.10, _skin_color)

	head_node = Node3D.new()
	head_node.name = "Head"
	head_node.position = Vector3(0.0, 0.76, 0.0)
	torso.add_child(head_node)
	_sphere(head_node, Vector3(0.0, 0.0, 0.0), 0.125, _skin_color)
	_box(head_node, Vector3(0.0, -0.01, -0.115), Vector3(0.035, 0.045, 0.03), _skin_color.darkened(0.05))
	_build_hair()
	_build_arm(true)
	_build_arm(false)
	_build_leg(true)
	_build_leg(false)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.72
	col.shape = cap
	col.position.y = 0.86
	add_child(col)


func _build_hair() -> void:
	var style := randi() % 6
	match style:
		0:
			_sphere(head_node, Vector3(0.0, 0.03, 0.01), 0.129, _hair_color)
			_box(head_node, Vector3(0.0, -0.05, 0.02), Vector3(0.24, 0.08, 0.22), _skin_color)
		1:
			_box(head_node, Vector3(0.0, 0.09, 0.0), Vector3(0.23, 0.10, 0.23), _hair_color)
			_box(head_node, Vector3(0.0, 0.03, 0.07), Vector3(0.24, 0.10, 0.12), _hair_color)
		2:
			_box(head_node, Vector3(0.0, 0.08, 0.0), Vector3(0.23, 0.10, 0.24), _hair_color)
			_box(head_node, Vector3(0.0, -0.06, 0.09), Vector3(0.22, 0.22, 0.08), _hair_color)
		3:
			_sphere(head_node, Vector3(0.0, 0.04, 0.02), 0.128, _hair_color)
			_sphere(head_node, Vector3(0.0, 0.02, 0.16), 0.055, _hair_color)
		4:
			_sphere(head_node, Vector3(0.0, 0.01, 0.015), 0.126, _hair_color.darkened(0.1))
			_box(head_node, Vector3(0.0, -0.07, 0.0), Vector3(0.23, 0.10, 0.22), _skin_color)
		5:
			_box(head_node, Vector3(0.0, 0.08, 0.0), Vector3(0.24, 0.08, 0.24), _hair_color)
			_box(head_node, Vector3(-0.11, -0.02, 0.0), Vector3(0.05, 0.18, 0.18), _hair_color)
			_box(head_node, Vector3(0.11, -0.02, 0.0), Vector3(0.05, 0.18, 0.18), _hair_color)


func _build_arm(is_left: bool) -> void:
	var side := -1.0 if is_left else 1.0
	var upper := Node3D.new()
	upper.name = "LeftUpperArm" if is_left else "RightUpperArm"
	upper.position = Vector3(side * 0.255, 0.50, 0.0)
	torso.add_child(upper)
	_cyl(upper, Vector3(0.0, -0.145, 0.0), 0.045, 0.29, _shirt_color)
	var lower := Node3D.new()
	lower.name = "LeftLowerArm" if is_left else "RightLowerArm"
	lower.position = Vector3(0.0, -0.29, 0.0)
	upper.add_child(lower)
	_cyl(lower, Vector3(0.0, -0.13, 0.0), 0.04, 0.26, _skin_color)
	_box(lower, Vector3(0.0, -0.285, 0.0), Vector3(0.065, 0.09, 0.045), _skin_color.darkened(0.03))
	if is_left:
		left_arm = upper
		left_lower_arm = lower
	else:
		right_arm = upper
		right_lower_arm = lower


func _build_leg(is_left: bool) -> void:
	var side := -1.0 if is_left else 1.0
	var upper := Node3D.new()
	upper.name = "LeftUpperLeg" if is_left else "RightUpperLeg"
	upper.position = Vector3(side * 0.095, -0.10, 0.0)
	hips.add_child(upper)
	_cyl(upper, Vector3(0.0, -0.215, 0.0), 0.07, 0.43, _pant_color)
	var lower := Node3D.new()
	lower.name = "LeftLowerLeg" if is_left else "RightLowerLeg"
	lower.position = Vector3(0.0, -0.43, 0.0)
	upper.add_child(lower)
	var shin_col := _pant_color.darkened(0.03)
	if _has_skirt:
		shin_col = _skin_color
	_cyl(lower, Vector3(0.0, -0.20, 0.0), 0.055, 0.40, shin_col)
	_box(lower, Vector3(0.0, -0.425, -0.045), Vector3(0.095, 0.07, 0.21), _shoe_color)
	if is_left:
		left_leg = upper
		left_lower_leg = lower
	else:
		right_leg = upper
		right_lower_leg = lower


func _apply_outfit_details() -> void:
	match _outfit:
		"office":
			_box(torso, Vector3(0.0, 0.34, -0.01), Vector3(0.34, 0.30, 0.22), _shirt_color.darkened(0.08))
		"worker":
			_box(torso, Vector3(0.0, 0.26, 0.0), Vector3(0.37, 0.34, 0.24), _shirt_color)
			_box(torso, Vector3(0.0, 0.06, -0.11), Vector3(0.18, 0.10, 0.03), Color("d8cf60"))
		"nightlife":
			_box(torso, Vector3(0.0, 0.30, 0.0), Vector3(0.33, 0.28, 0.21), _shirt_color)
		"streetwear":
			_box(torso, Vector3(0.0, 0.30, 0.0), Vector3(0.39, 0.34, 0.25), _shirt_color)
			_box(torso, Vector3(0.0, 0.18, -0.13), Vector3(0.12, 0.14, 0.04), _shirt_color.darkened(0.12))
		"police":
			# Generic NSW-inspired uniform colours/shape (no official insignia).
			_shirt_color = Color("1d3557")
			_pant_color = Color("1a2740")
			_box(torso, Vector3(0.0, 0.34, 0.0), Vector3(0.37, 0.30, 0.23), _shirt_color)
			_box(hips, Vector3(0.0, -0.12, 0.0), Vector3(0.36, 0.05, 0.24), Color("1a1a1a"))
			_box(torso, Vector3(0.10, 0.44, -0.12), Vector3(0.05, 0.03, 0.02), Color("d4af37"))
		"rough":
			_box(torso, Vector3(0.0, 0.30, 0.0), Vector3(0.36, 0.30, 0.23), _shirt_color.darkened(0.1))
	if _has_skirt:
		_box(hips, Vector3(0.0, -0.18, 0.0), Vector3(0.36, 0.22, 0.24), _shirt_color.darkened(0.05))
	if _has_hat or _outfit == "worker":
		_cyl(head_node, Vector3(0.0, 0.12, 0.0), 0.145, 0.05, _pant_color.darkened(0.1))
		_cyl(head_node, Vector3(0.0, 0.09, 0.0), 0.11, 0.08, _pant_color.darkened(0.1))


func _build_props() -> void:
	if _has_bag or _outfit in ["office", "streetwear"]:
		_bag = Node3D.new()
		torso.add_child(_bag)
		_box(_bag, Vector3(0.0, 0.18, 0.16), Vector3(0.22, 0.28, 0.10), Color("2d2d2d") if _outfit != "office" else Color("4a3728"))
	_phone = Node3D.new()
	_phone.visible = false
	if right_lower_arm != null:
		right_lower_arm.add_child(_phone)
		_box(_phone, Vector3(0.0, -0.27, -0.05), Vector3(0.045, 0.085, 0.01), Color("202225"))
	_cigarette = Node3D.new()
	_cigarette.visible = false
	if right_lower_arm != null:
		right_lower_arm.add_child(_cigarette)
		_cyl(_cigarette, Vector3(0.0, -0.27, -0.08), 0.006, 0.07, Color("f5f1e6"))
		var tip := MeshInstance3D.new()
		var ts := CylinderMesh.new()
		ts.top_radius = 0.0065
		ts.bottom_radius = 0.0065
		ts.height = 0.012
		tip.mesh = ts
		var tm := StandardMaterial3D.new()
		tm.albedo_color = Color("ff6a00")
		tm.emission_enabled = true
		tm.emission = Color("ff7a1a")
		tm.emission_energy_multiplier = 1.5
		tip.material_override = tm
		_cigarette.add_child(tip)
		tip.position = Vector3(0.0, -0.27, -0.118)
	_smoke = Node3D.new()
	_smoke.visible = false
	if _cigarette != null:
		_cigarette.add_child(_smoke)
		_sphere(_smoke, Vector3(0.0, -0.24, -0.16), 0.03, Color(0.85, 0.85, 0.88, 0.25))
	_cup = Node3D.new()
	_cup.visible = false
	if left_lower_arm != null:
		left_lower_arm.add_child(_cup)
		_cyl(_cup, Vector3(0.0, -0.27, -0.05), 0.03, 0.08, Color("efe7dc"))

	# Subtle near-future accessories — ordinary people, not robots. Headphones
	# for commuters/young adults, a small lit bag strap for nightlife crowds.
	if _archetype in ["commuter", "student", "young_adult", "office"] and randf() < 0.35 and head_node != null:
		_cyl(head_node, Vector3(-0.125, 0.0, 0.0), 0.035, 0.02, Color("1a1d22"))
		_cyl(head_node, Vector3(0.125, 0.0, 0.0), 0.035, 0.02, Color("1a1d22"))
		_box(head_node, Vector3(0.0, 0.11, 0.0), Vector3(0.25, 0.025, 0.05), Color("1a1d22"))
	if _archetype in ["nightlife", "street_group"] and _bag != null and randf() < 0.5:
		var led := MeshInstance3D.new()
		var led_shape := BoxMesh.new()
		led_shape.size = Vector3(0.02, 0.30, 0.02)
		led.mesh = led_shape
		var led_mat := StandardMaterial3D.new()
		led_mat.emission_enabled = true
		led_mat.emission = Color("19e6ff")
		led_mat.emission_energy_multiplier = 0.8
		led.material_override = led_mat
		_bag.add_child(led)
		led.position = Vector3(0.12, 0.18, 0.1)


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = Art.mat(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh


func _cyl(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	mesh.mesh = shape
	mesh.material_override = Art.mat(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh


func _sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	mesh.mesh = shape
	mesh.material_override = Art.mat(color)
	parent.add_child(mesh)
	mesh.position = pos
	return mesh


## Enter a brief self-preservation state, then resume the normal routine.
func react_to_threat(threat_position: Vector3, duration: float = 3.0) -> void:
	if is_dead or duration <= 0.0:
		return
	var away := global_position - threat_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	_flee_dir = away.normalized()
	if _flee_time <= 0.0:
		_prior_activity = activity
	_flee_time = maxf(_flee_time, clampf(duration, 0.4, 6.0))
	is_waiting = false
	activity = Activity.WALK


func _check_vehicle_proximity() -> void:
	var cars := get_tree().get_nodes_in_group("traffic_vehicles")
	for car: Node in cars:
		if not (car is Node3D):
			continue
		var offset := (car as Node3D).global_position - global_position
		offset.y = 0.0
		var dist_sq := offset.length_squared()
		if dist_sq < 49.0:
			var forward: Vector3 = -(car as Node3D).global_transform.basis.z
			var approaching := forward.dot(-offset.normalized()) > 0.25
			if approaching and dist_sq < 25.0:
				react_to_threat((car as Node3D).global_position, 1.8)
				return


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var step := delta
	_avoid_check += delta
	if _avoid_check >= 0.5:
		_avoid_check = 0.0
		_check_vehicle_proximity()
	if _flee_time > 0.0:
		_flee_time -= step
		var speed := walk_speed * 1.7
		var scaled := speed * (step / maxf(get_physics_process_delta_time(), 0.0001))
		velocity.x = _flee_dir.x * scaled
		velocity.z = _flee_dir.z * scaled
		velocity.y -= 9.8 * step
		rotation.y = atan2(-_flee_dir.x, -_flee_dir.z)
		move_and_slide()
		_animate_walking(speed, step)
		if _flee_time <= 0.0:
			activity = _prior_activity
			_pick_next_target()
		return
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

	_activity_timer -= step
	_gesture_time += step

	if activity in [Activity.STAND, Activity.TALK, Activity.PHONE, Activity.SMOKE, Activity.SIT, Activity.LOITER] or is_waiting:
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * step)
		velocity.z = move_toward(velocity.z, 0.0, 6.0 * step)
		velocity.y -= 9.8 * step
		move_and_slide()
		if is_waiting:
			wait_timer -= step
			if wait_timer <= 0.0:
				is_waiting = false
				activity = Activity.WALK
				_pick_next_target()
		elif _activity_timer <= 0.0:
			_switch_activity()
		_apply_activity_pose(step)
		return

	if not (target_node_id in graph_nodes):
		_pick_next_target()
		_apply_activity_pose(step)
		return

	var target_data: Dictionary = graph_nodes[target_node_id]
	var target_pos := Vector3(float(target_data["x"]), global_position.y, float(target_data["z"]))
	var diff := target_pos - global_position
	diff.y = 0.0
	var dist := diff.length()

	if dist < 1.0:
		current_node_id = target_node_id
		if randf() < 0.28:
			is_waiting = true
			wait_timer = randf_range(1.5, 6.0)
			activity = [Activity.STAND, Activity.PHONE, Activity.TALK, Activity.WAIT_CROSS, Activity.LOITER][randi() % 5]
		else:
			_pick_next_target()
		_apply_activity_pose(step)
		return

	var fwd := diff.normalized()
	var step_scale := step / maxf(get_physics_process_delta_time(), 0.0001)
	velocity.x = fwd.x * walk_speed * step_scale
	velocity.z = fwd.z * walk_speed * step_scale
	velocity.y -= 9.8 * step
	rotation.y = atan2(-fwd.x, -fwd.z)
	move_and_slide()
	_animate_walking(walk_speed, step)


func _switch_activity() -> void:
	var choices := [Activity.WALK, Activity.WALK, Activity.STAND, Activity.PHONE, Activity.TALK, Activity.LOITER]
	if _archetype == "sex_worker":
		choices = [Activity.STAND, Activity.STAND, Activity.TALK, Activity.LOITER, Activity.WALK]
	elif _archetype == "drug_affected":
		choices = [Activity.LOITER, Activity.LOITER, Activity.STAND, Activity.WALK, Activity.WALK]
	activity = choices[randi() % choices.size()]
	_activity_timer = randf_range(3.0, 14.0)
	if activity == Activity.WALK:
		_pick_next_target()


func _apply_activity_pose(delta: float) -> void:
	var walking := (activity == Activity.WALK) and velocity.length() > 0.15 and not is_waiting
	if _phone != null:
		_phone.visible = (activity == Activity.PHONE)
	if _cigarette != null:
		_cigarette.visible = (activity == Activity.SMOKE)
	if _smoke != null:
		_smoke.visible = (activity == Activity.SMOKE)
	if _cup != null:
		_cup.visible = false

	if walking:
		_animate_walking(walk_speed, delta)
		return

	_animate_walking(0.0, delta)
	if activity == Activity.PHONE and right_arm != null and right_lower_arm != null:
		right_arm.rotation.x = lerpf(right_arm.rotation.x, -1.1, delta * 6.0)
		right_lower_arm.rotation.x = lerpf(right_lower_arm.rotation.x, -1.0, delta * 6.0)
		if head_node != null:
			head_node.rotation.x = lerpf(head_node.rotation.x, 0.18, delta * 4.0)
	elif activity == Activity.SMOKE and right_arm != null and right_lower_arm != null:
		right_arm.rotation.x = lerpf(right_arm.rotation.x, -1.25, delta * 5.0)
		right_lower_arm.rotation.x = lerpf(right_lower_arm.rotation.x, -1.35, delta * 5.0)
	elif activity == Activity.TALK and left_arm != null and right_arm != null:
		var g := sin(_gesture_time * 3.0) * 0.18
		left_arm.rotation.x = lerpf(left_arm.rotation.x, -0.45 + g, delta * 5.0)
		right_arm.rotation.x = lerpf(right_arm.rotation.x, -0.35 - g, delta * 5.0)
	elif activity == Activity.SIT and left_leg != null and right_leg != null:
		if hips != null:
			hips.position.y = lerpf(hips.position.y, 0.58, delta * 4.0)
		left_leg.rotation.x = lerpf(left_leg.rotation.x, -1.35, delta * 6.0)
		right_leg.rotation.x = lerpf(right_leg.rotation.x, -1.35, delta * 6.0)
		if left_lower_leg != null:
			left_lower_leg.rotation.x = lerpf(left_lower_leg.rotation.x, 1.3, delta * 6.0)
		if right_lower_leg != null:
			right_lower_leg.rotation.x = lerpf(right_lower_leg.rotation.x, 1.3, delta * 6.0)
	elif activity == Activity.LOITER:
		if torso != null:
			torso.rotation.y = lerpf(torso.rotation.y, sin(_gesture_time * 1.4) * 0.12, delta * 3.0)

	if activity != Activity.SIT and hips != null:
		hips.position.y = lerpf(hips.position.y, 0.93, delta * 4.0)


func take_damage_at(amount: float, impact_position: Vector3, impact_intensity: float = 1.0, shot_direction: Vector3 = Vector3.FORWARD) -> void:
	if is_dead:
		return
	health = maxf(0.0, health - amount)
	var was_alive := health > 0.0
	GoreEffectsScript.spawn_hit_spray(get_parent(), impact_position, impact_intensity, shot_direction)
	if _archetype == "police" and was_alive:
		# Visible flinch / reaction to being shot.
		_reaction = 0.5
		if torso != null:
			torso.rotation.x = -0.25
	if not was_alive:
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
	var wanted := get_tree().get_first_node_in_group("wanted_system")
	if _archetype == "police":
		remove_from_group("police_foot_patrol")
		if wanted != null and wanted.has_method("officer_killed"):
			wanted.call("officer_killed", global_position)
	elif wanted != null:
		wanted.add_crime(18.0, "PEDESTRIAN KILLED · police alerted")
	is_dead = true
	set_physics_process(false)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	for shape: CollisionShape3D in find_children("*", "CollisionShape3D", true, false):
		shape.set_deferred("disabled", true)
	if body_root != null:
		body_root.visible = false
	GoreEffectsScript.spawn_body_destruction(get_parent(), global_position, launch_velocity, _skin_color, _shirt_color)
	var cleanup := get_tree().create_timer(1.0)
	cleanup.timeout.connect(queue_free)


func _animate_walking(spd: float, delta: float) -> void:
	if spd > 0.1:
		walk_anim_time += delta * spd * 4.2
		idle_anim_time = 0.0
		var swing := sin(walk_anim_time) * 0.5
		var lift := maxf(0.0, sin(walk_anim_time)) * 0.25
		var lift_r := maxf(0.0, sin(walk_anim_time + PI)) * 0.25
		_set_limb_pose(swing, lift, lift_r, delta)
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, -0.03, delta * 5.0)
			torso.rotation.y = sin(walk_anim_time * 0.5) * 0.04
		if head_node != null:
			head_node.rotation.x = lerpf(head_node.rotation.x, 0.02, delta * 4.0)
	else:
		idle_anim_time += delta
		var breathe := sin(idle_anim_time * 1.8) * 0.015
		_set_limb_pose(0.0, 0.0, 0.0, delta)
		if torso != null:
			torso.rotation.x = lerpf(torso.rotation.x, breathe, delta * 3.0)
			torso.rotation.y = lerpf(torso.rotation.y, 0.0, delta * 3.0)
		if head_node != null:
			head_node.rotation.x = lerpf(head_node.rotation.x, 0.0, delta * 3.0)
			head_node.rotation.y = lerpf(head_node.rotation.y, sin(idle_anim_time * 0.6) * 0.03, delta * 2.0)


func _set_limb_pose(swing: float, lift_l: float, lift_r: float, delta: float) -> void:
	var rate := 10.0
	if left_leg != null:
		left_leg.rotation.x = lerpf(left_leg.rotation.x, swing, delta * rate)
	if right_leg != null:
		right_leg.rotation.x = lerpf(right_leg.rotation.x, -swing, delta * rate)
	if left_lower_leg != null:
		left_lower_leg.rotation.x = lerpf(left_lower_leg.rotation.x, -lift_l, delta * rate)
	if right_lower_leg != null:
		right_lower_leg.rotation.x = lerpf(right_lower_leg.rotation.x, -lift_r, delta * rate)
	if left_arm != null:
		left_arm.rotation.x = lerpf(left_arm.rotation.x, -swing * 0.75, delta * rate)
	if right_arm != null:
		right_arm.rotation.x = lerpf(right_arm.rotation.x, swing * 0.75, delta * rate)
	if left_lower_arm != null:
		left_lower_arm.rotation.x = lerpf(left_lower_arm.rotation.x, -0.15 - maxf(0.0, swing) * 0.2, delta * rate)
	if right_lower_arm != null:
		right_lower_arm.rotation.x = lerpf(right_lower_arm.rotation.x, -0.15 - maxf(0.0, -swing) * 0.2, delta * rate)
