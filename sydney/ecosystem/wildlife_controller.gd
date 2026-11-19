class_name WildlifeController
extends CharacterBody3D

const GoreEffectsScript := preload("res://scripts/gore_effects.gd")

## Sydney Wildlife Agent: Australian White Ibis ("bin chicken"), Seagull, Pigeon.
## Features authentic proportions, walking, pecking, scavenging around bins/crumbs,
## and player avoidance reactions.

enum WildlifeKind {
	IBIS,
	SEAGULL,
	PIGEON
}

@export var kind: int = WildlifeKind.IBIS

var move_speed: float = 1.6
var wander_origin: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var state_timer: float = 0.0
var state: String = "idle" # "idle", "walk", "peck", "flee"

var player_ref: Node3D

# Visual hierarchy
var body_root: Node3D
var neck_joint: Node3D
var head_node: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_wing: Node3D
var right_wing: Node3D

var anim_time: float = 0.0
var _vehicle_hit: bool = false
## Distance LOD; background birds do not need 60 Hz physics.
var _sim_accum: float = 0.0

func _ready() -> void:
	add_to_group("wildlife")
	_build_visuals()
	wander_origin = global_position
	_pick_new_state()

func hit_by_vehicle(impact_speed: float, source: Node3D = null) -> bool:
	if _vehicle_hit or impact_speed < 3.0:
		return false
	_vehicle_hit = true
	var launch := Vector3.FORWARD * impact_speed
	if source != null and "velocity" in source:
		launch = source.get("velocity")
	if launch.length() < 3.0:
		launch = Vector3.FORWARD * impact_speed
	_die(launch)
	var player_vehicle: Object = player_ref.get("vehicle") if is_instance_valid(player_ref) else null
	var player_caused_hit := source == player_ref or source == player_vehicle
	if kind == WildlifeKind.IBIS and player_caused_hit and is_instance_valid(player_ref) \
	and player_ref.has_method("award_bin_chicken_bonus"):
		player_ref.call("award_bin_chicken_bonus")
	return true


func take_damage_at(
	amount: float,
	impact_position: Vector3,
	impact_intensity: float = 1.0,
	shot_direction: Vector3 = Vector3.FORWARD
) -> void:
	if _vehicle_hit:
		return
	GoreEffectsScript.spawn_hit_spray(get_parent(),impact_position,impact_intensity,shot_direction)
	_die(shot_direction.normalized() * impact_intensity * 6.0)


func take_damage(amount: float) -> void:
	take_damage_at(amount, global_position + Vector3.UP * 0.3, 1.0, Vector3.FORWARD)


func _die(launch: Vector3) -> void:
	if _vehicle_hit:
		return
	_vehicle_hit = true
	set_physics_process(false)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	for shape: CollisionShape3D in find_children("*","CollisionShape3D",true,false):
		shape.set_deferred("disabled",true)
	if body_root != null:
		body_root.visible = false
	GoreEffectsScript.spawn_body_destruction(
		get_parent(), global_position, launch,
		Color("f7f7f7"), Color("141416"), true
	)
	_spawn_impact_effect()
	var cleanup := get_tree().create_timer(5.0)
	cleanup.timeout.connect(queue_free)

func _spawn_impact_effect() -> void:
	GoreEffectsScript.spawn_death_splatter(get_parent(),global_position,1.25,true)
	var cleanup := get_tree().create_timer(5.0)
	cleanup.timeout.connect(queue_free)

func setup(p_kind: int, p_pos: Vector3, player: Node3D) -> void:
	var previous_kind := kind
	kind = p_kind
	global_position = p_pos
	wander_origin = p_pos
	player_ref = player
	# `_ready()` already built the default (ibis) visual. Rebuild only when the
	# requested species differs, instead of always freeing and rebuilding.
	if body_root == null or kind != previous_kind:
		_build_visuals()

func _build_visuals() -> void:
	for child in get_children():
		if child is Node3D and child.name == "BodyVisuals":
			child.queue_free()
	
	body_root = Node3D.new()
	body_root.name = "BodyVisuals"
	add_child(body_root)
	
	match kind:
		WildlifeKind.IBIS:
			# --- Australian White Ibis ("Bin Chicken") ---
			# Body: Pure white body with dirty grey feather hints
			# Neck & Head: Naked black skin, slender and curved
			# Beak: Distinctive long, downward-curving black sickle beak
			# Legs: Long, slender dark legs
			
			var white_col := Color("f7f7f7")
			var black_skin := Color("141416")
			var beak_col := Color("0d0d0f")
			
			# Body
			Art.box(body_root, Vector3(0, 0.42, 0), Vector3(0.24, 0.22, 0.42), white_col)
			# Black scruffy tail plumes
			Art.box(body_root, Vector3(0, 0.46, 0.24), Vector3(0.18, 0.14, 0.16), black_skin)
			
			# Long slender neck joint (for pecking animation)
			neck_joint = Node3D.new()
			neck_joint.position = Vector3(0, 0.48, -0.18)
			body_root.add_child(neck_joint)
			
			# S-curved black naked neck
			Art.cylinder(neck_joint, Vector3(0, 0.16, -0.06), 0.035, 0.32, black_skin)
			
			# Naked black head
			head_node = Node3D.new()
			head_node.position = Vector3(0, 0.32, -0.1)
			neck_joint.add_child(head_node)
			Art.box(head_node, Vector3(0, 0, 0), Vector3(0.09, 0.08, 0.14), black_skin)
			
			# Iconic long curved black beak (sickle curve composed of segments)
			Art.box(head_node, Vector3(0, -0.02, -0.12), Vector3(0.03, 0.03, 0.14), beak_col)
			var beak_tip := Art.box(head_node, Vector3(0, -0.09, -0.22), Vector3(0.022, 0.022, 0.14), beak_col)
			beak_tip.rotation.x = 0.45 # downward arc curve
			
			# Long legs
			left_leg = Node3D.new()
			left_leg.position = Vector3(-0.08, 0.32, 0)
			body_root.add_child(left_leg)
			Art.cylinder(left_leg, Vector3(0, -0.16, 0), 0.015, 0.34, black_skin)
			# Toes
			Art.box(left_leg, Vector3(0, -0.32, -0.05), Vector3(0.08, 0.015, 0.12), black_skin)
			
			right_leg = Node3D.new()
			right_leg.position = Vector3(0.08, 0.32, 0)
			body_root.add_child(right_leg)
			Art.cylinder(right_leg, Vector3(0, -0.16, 0), 0.015, 0.34, black_skin)
			Art.box(right_leg, Vector3(0, -0.32, -0.05), Vector3(0.08, 0.015, 0.12), black_skin)

		WildlifeKind.SEAGULL:
			# Harbour Seagull: grey/white wings, yellow beak with red spot
			var white_col := Color("ffffff")
			var grey_col := Color("90a4ae")
			var beak_col := Color("ffb300")
			
			Art.box(body_root, Vector3(0, 0.22, 0), Vector3(0.16, 0.16, 0.28), white_col)
			Art.box(body_root, Vector3(0, 0.24, 0.04), Vector3(0.18, 0.12, 0.22), grey_col) # Wings
			
			neck_joint = Node3D.new()
			neck_joint.position = Vector3(0, 0.26, -0.12)
			body_root.add_child(neck_joint)
			Art.box(neck_joint, Vector3(0, 0.08, -0.04), Vector3(0.08, 0.12, 0.10), white_col) # Head
			Art.box(neck_joint, Vector3(0, 0.06, -0.14), Vector3(0.025, 0.03, 0.12), beak_col) # Yellow beak
			
			left_leg = Node3D.new()
			left_leg.position = Vector3(-0.05, 0.14, 0)
			body_root.add_child(left_leg)
			Art.cylinder(left_leg, Vector3(0, -0.07, 0), 0.01, 0.14, Color("f57c00"))
			
			right_leg = Node3D.new()
			right_leg.position = Vector3(0.05, 0.14, 0)
			body_root.add_child(right_leg)
			Art.cylinder(right_leg, Vector3(0, -0.07, 0), 0.01, 0.14, Color("f57c00"))

		WildlifeKind.PIGEON:
			# City Pigeon: Iridescent blue-grey neck, grey body
			var slate_grey := Color("546e7a")
			var green_shimmer := Color("26a69a")
			
			Art.box(body_root, Vector3(0, 0.16, 0), Vector3(0.13, 0.14, 0.22), slate_grey)
			neck_joint = Node3D.new()
			neck_joint.position = Vector3(0, 0.20, -0.08)
			body_root.add_child(neck_joint)
			Art.cylinder(neck_joint, Vector3(0, 0.06, -0.02), 0.035, 0.10, green_shimmer)
			Art.box(neck_joint, Vector3(0, 0.11, -0.03), Vector3(0.06, 0.06, 0.08), slate_grey)
			Art.box(neck_joint, Vector3(0, 0.09, -0.09), Vector3(0.018, 0.02, 0.06), Color("212121"))
			
			left_leg = Node3D.new()
			left_leg.position = Vector3(-0.04, 0.10, 0)
			body_root.add_child(left_leg)
			Art.cylinder(left_leg, Vector3(0, -0.05, 0), 0.008, 0.10, Color("d81b60"))
			
			right_leg = Node3D.new()
			right_leg.position = Vector3(0.04, 0.10, 0)
			body_root.add_child(right_leg)
			Art.cylinder(right_leg, Vector3(0, -0.05, 0), 0.008, 0.10, Color("d81b60"))
	
	# Lightweight collision shape
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 0.65
	col.shape = cap
	col.position.y = 0.35
	add_child(col)

func _physics_process(delta: float) -> void:
	var step := delta
	var dist_to_player := INF
	# React to player proximity (flee if player runs close)
	if player_ref != null:
		dist_to_player = global_position.distance_to(player_ref.global_position)
		var interval := 0.0
		if dist_to_player > 60.0:
			interval = 1.0 / 15.0
		elif dist_to_player > 25.0:
			interval = 1.0 / 30.0
		if interval > 0.0:
			_sim_accum += delta
			if _sim_accum < interval:
				return
			step = _sim_accum
			_sim_accum = 0.0
		if dist_to_player < 3.5 and state != "flee":
			state = "flee"
			state_timer = 2.5
			var away := (global_position - player_ref.global_position).normalized()
			target_pos = global_position + away * 6.0
	
	state_timer -= step
	if state_timer <= 0.0:
		_pick_new_state()
	
	var step_scale := step / maxf(get_physics_process_delta_time(), 0.0001)
	match state:
		"walk", "flee":
			var diff := target_pos - global_position
			diff.y = 0.0
			var dist := diff.length()
			if dist < 0.4:
				_pick_new_state()
			else:
				var spd := move_speed * (2.2 if state == "flee" else 1.0)
				var fwd := diff.normalized()
				velocity.x = fwd.x * spd * step_scale
				velocity.z = fwd.z * spd * step_scale
				velocity.y -= 9.8 * step
				rotation.y = atan2(-fwd.x, -fwd.z)
				move_and_slide()
				_animate_locomotion(spd, step)
		"peck":
			velocity = Vector3(0, -9.8 * step, 0)
			move_and_slide()
			_animate_pecking(step)
		"idle":
			velocity = Vector3(0, -9.8 * step, 0)
			move_and_slide()
			_animate_idle(step)

func _pick_new_state() -> void:
	var roll := randf()
	if roll < 0.35:
		# Pecking for bin crumbs
		state = "peck"
		state_timer = randf_range(1.5, 4.0)
	elif roll < 0.75:
		# Wandering
		state = "walk"
		state_timer = randf_range(2.0, 5.0)
		var angle := randf() * TAU
		var radius := randf_range(2.0, 8.0)
		target_pos = wander_origin + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
	else:
		state = "idle"
		state_timer = randf_range(1.0, 3.0)

func _animate_locomotion(spd: float, delta: float) -> void:
	anim_time += delta * spd * 7.0
	var leg_angle := sin(anim_time) * 0.5
	if left_leg != null:
		left_leg.rotation.x = leg_angle
	if right_leg != null:
		right_leg.rotation.x = -leg_angle
	# Distinctive ibis head bobbing while walking
	if neck_joint != null:
		neck_joint.rotation.x = sin(anim_time * 2.0) * 0.15

func _animate_pecking(delta: float) -> void:
	anim_time += delta * 6.0
	var peck_dip := maxf(0.0, sin(anim_time)) * 0.7
	if neck_joint != null:
		neck_joint.rotation.x = peck_dip

func _animate_idle(delta: float) -> void:
	if neck_joint != null:
		neck_joint.rotation.x = move_toward(neck_joint.rotation.x, 0.0, delta * 2.0)
	if left_leg != null:
		left_leg.rotation.x = move_toward(left_leg.rotation.x, 0.0, delta * 2.0)
	if right_leg != null:
		right_leg.rotation.x = move_toward(right_leg.rotation.x, 0.0, delta * 2.0)
