class_name Skateboard
extends CharacterBody3D

## Skateboard traversal: carve, ollie, tricks, rail/ledge grinding and boost.
## The player is hidden and carried with the board; the existing camera rig
## follows the player position, so no separate camera system is introduced.

const GRIND_SPEED_MIN := 5.0
const BOOST_CAPACITY := 100.0
const BOOST_DRAIN := 45.0
const BOOST_RECHARGE := 12.0

var driver: Node3D
var speed := 0.0
var lean := 0.0
var steering := 0.0
var grinding := false
var grind_dir := Vector3.FORWARD
var airborne := false
var ollie := false
var trick_spin := 0.0
var boost_amount := BOOST_CAPACITY
var boosting := false
var airborne_time := 0.0
var trick_name := ""
var board_visual: Node3D
var rider_visual: Node3D

var _grind_stable := 0.0
var _launch_this_frame := 0.0
var _air_vy := 0.0
var _trick_cooldown := 0.0
var _jump_buffer := 0.0


func _ready() -> void:
	add_to_group("skateboards")
	floor_snap_length = 0.25
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.35, 0.12, 0.9)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.08
	add_child(col)
	_build_visuals()


func _build_visuals() -> void:
	board_visual = Node3D.new()
	board_visual.name = "BoardVisual"
	add_child(board_visual)
	Art.box(board_visual, Vector3(0, 0.12, 0), Vector3(0.34, 0.06, 0.95), Color("b5482b"))
	Art.box(board_visual, Vector3(0, 0.12, 0), Vector3(0.30, 0.02, 0.88), Color("2d2a26"))
	for z in [-0.30, 0.30]:
		Art.cylinder(board_visual, Vector3(0, 0.05, z), 0.06, 0.36, Color("c9c4b8")).rotation.z = PI * 0.5
	rider_visual = Node3D.new()
	rider_visual.name = "Rider"
	board_visual.add_child(rider_visual)
	var pants := Color("2b3442")
	var shirt := Color("b5472f")
	Art.box(rider_visual, Vector3(0, 0.78, 0.0), Vector3(0.34, 0.48, 0.24), shirt)
	Art.box(rider_visual, Vector3(0, 1.12, -0.02), Vector3(0.20, 0.22, 0.2), Color("c68642"))
	Art.box(rider_visual, Vector3(0, 1.27, -0.02), Vector3(0.24, 0.11, 0.24), Color("1e1a16"))
	for side in [-1, 1]:
		Art.box(rider_visual, Vector3(side * 0.12, 0.38, 0.04), Vector3(0.14, 0.55, 0.16), pants)
		Art.box(rider_visual, Vector3(side * 0.13, 0.10, -0.06), Vector3(0.14, 0.1, 0.28), Color("111418"))
		Art.box(rider_visual, Vector3(side * 0.25, 0.85, 0.0), Vector3(0.09, 0.48, 0.1), shirt)


func mount(player: Node3D) -> void:
	driver = player
	global_position = player.global_position
	velocity = Vector3.ZERO
	speed = 0.0
	player.visible = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.set_meta("skateboard", self)


func dismount() -> void:
	if driver != null and is_instance_valid(driver):
		driver.visible = true
		driver.collision_layer = 1
		driver.collision_mask = 1
		driver.global_position = global_position + Vector3.UP * 0.3
		driver.velocity = Vector3.ZERO
		driver.remove_meta("skateboard")
	driver = null
	queue_free()


func _physics_process(dt: float) -> void:
	if driver == null or not is_instance_valid(driver):
		return
	# Carry the (invisible) player so the existing camera rig follows the board.
	driver.global_position = global_position
	_trick_cooldown = maxf(0.0, _trick_cooldown - dt)
	_jump_buffer = maxf(0.0, _jump_buffer - dt)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.12

	boosting = Input.is_action_pressed("skate_boost") and boost_amount > 1.0 and not grinding
	if boosting:
		boost_amount = maxf(0.0, boost_amount - BOOST_DRAIN * dt)
	else:
		boost_amount = minf(BOOST_CAPACITY, boost_amount + BOOST_RECHARGE * dt)

	var throttle := Input.get_axis("back", "forward")
	var turn := Input.get_axis("left", "right")
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.01 else Vector3.FORWARD

	if grinding:
		_grind(dt, turn)
	else:
		var boost_force := 14.0 if boosting else 0.0
		var accel := 7.0 + boost_force
		if throttle > 0.0:
			speed = minf(speed + accel * dt, 26.0 if boosting else 16.0)
		elif throttle < 0.0:
			speed = maxf(speed - 18.0 * dt, -4.0)
		else:
			speed = move_toward(speed, 0.0, 3.0 * dt)
		var turn_rate := 2.6 if absf(speed) > 1.0 else 1.0
		steering = lerpf(steering, -turn * turn_rate, 1.0 - exp(-9.0 * dt))
		if not airborne:
			rotate_y(steering * dt * clampf(absf(speed) / 5.0, 0.3, 1.4))
		lean = lerpf(lean, -turn * clampf(absf(speed) / 14.0, 0.0, 1.0), 1.0 - exp(-8.0 * dt))

		if _jump_buffer > 0.0 and is_on_floor():
			_do_ollie()
		_handle_tricks(dt)
		velocity = forward * speed + Vector3.DOWN * 2.0
		# The board needs real vertical momentum while airborne: the per-frame
		# rebuild above would otherwise pin velocity.y to -2 and the ollie's
		# launch arc (and any ledge drop) never happens.
		if airborne or _launch_this_frame > 0.0:
			if _launch_this_frame > 0.0:
				_air_vy = _launch_this_frame
				_launch_this_frame = 0.0
			_air_vy = maxf(_air_vy - 24.0 * dt, -32.0)
			velocity.y = _air_vy
		velocity.y = maxf(velocity.y, -32.0)
		move_and_slide()
		airborne = not is_on_floor()
		if airborne:
			airborne_time += dt
		else:
			_air_vy = 0.0
			airborne_time = 0.0
			ollie = false
			trick_name = ""
		_check_grind_entry()

	_update_visual(dt)


func _do_ollie() -> void:
	_jump_buffer = 0.0
	_launch_this_frame = 7.5 if speed > 9.0 else 5.8
	velocity.y = _launch_this_frame
	airborne = true
	ollie = true
	airborne_time = 0.0


func _handle_tricks(dt: float) -> void:
	if not airborne or _trick_cooldown > 0.0:
		return
	if Input.is_action_just_pressed("skate_trick"):
		var tricks := ["KICKFLIP", "HEELFLIP", "SHUVIT", "360 FLIP"]
		trick_name = tricks[randi() % tricks.size()]
		trick_spin = TAU if trick_name == "360 FLIP" else PI
		_trick_cooldown = 0.45
	if absf(Input.get_axis("left", "right")) > 0.5:
		trick_name = "KICKTURN"
		trick_spin += Input.get_axis("left", "right") * 3.0 * dt


func _check_grind_entry() -> void:
	if speed < GRIND_SPEED_MIN or airborne_time < 0.08:
		return
	if velocity.y > 0.0:
		return
	var origin := global_position + Vector3.UP * 0.4
	var down := Vector3.DOWN * 1.2
	var query := PhysicsRayQueryParameters3D.create(origin, origin + down, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var n: Vector3 = hit.normal
	if n.y < 0.65:
		return
	# `intersect_ray` returns an untyped Dictionary, so the component needs an
	# explicit type: `:=` cannot infer it and the whole script fails to parse.
	var h: float = hit.position.y
	if absf(h - (global_position.y + 0.1)) > 0.9:
		return
	grinding = true
	grind_dir = -global_transform.basis.z
	grind_dir.y = 0.0
	grind_dir = grind_dir.normalized()
	_grind_stable = 0.0
	trick_name = "GRIND"


func _grind(dt: float, turn: float) -> void:
	_grind_stable += dt
	var turn_rate := 0.9 if speed > 8.0 else 0.4
	var yaw := atan2(-grind_dir.x, -grind_dir.z) + turn * turn_rate * dt
	grind_dir = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var tangent := grind_dir
	velocity = tangent * maxf(speed, GRIND_SPEED_MIN) + Vector3.DOWN * 2.0
	move_and_slide()
	speed = maxf(speed - 1.2 * dt, GRIND_SPEED_MIN)
	if _jump_buffer > 0.0 or _grind_stable > 3.5:
		grinding = false
		_jump_buffer = 0.0
		_air_vy = 7.0
		velocity.y = 7.0
		airborne = true
		trick_name = "GRIND OUT"
		_grind_stable = 0.0


func _update_visual(dt: float) -> void:
	if board_visual == null:
		return
	board_visual.rotation.z = lean * 0.5
	if rider_visual != null:
		rider_visual.rotation.x = lerpf(rider_visual.rotation.x, 0.12 if grinding else -0.1, 1.0 - exp(-8.0 * dt))
		if trick_spin > 0.0 and airborne:
			board_visual.rotation.y += trick_spin * dt
			trick_spin = maxf(0.0, trick_spin - TAU * dt)
		else:
			board_visual.rotation.y = lerpf(board_visual.rotation.y, 0.0, 1.0 - exp(-6.0 * dt))
	if grinding:
		var yaw := atan2(-grind_dir.x, -grind_dir.z)
		rotation.y = lerpf(rotation.y, yaw, 1.0 - exp(-10.0 * dt))
