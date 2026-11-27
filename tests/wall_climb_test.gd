extends SceneTree

## Wall climbing (ported from SKYJUMP3D) in the real game scene:
##   A) a tall wall: latch on by pressing into it in the air, climb up, then wall-jump off;
##   B) a low ledge: climbing into it mantles onto the top.
## Walls are built in open air far above the city so nothing else interferes.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/wall_climb_test.gd

var checks := 0
var failures := 0
var scene: Node3D
var player: BoomPlayer


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _initialize() -> void:
	call_deferred("run")


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	scene.add_child(body)
	return body


func _place(pos: Vector3) -> void:
	# The camera drifts while the player falls, so pin it again for every case.
	player.world.rig.yaw = -PI / 2.0
	player.global_position = pos
	player.velocity = Vector3.ZERO
	await _frames(4)


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	player = scene.get_node_or_null("Player")
	if player == null:
		var found := get_nodes_in_group("player")
		player = found[0] if not found.is_empty() else null
	check(player != null, "player resolved")
	if player == null:
		quit(1)
		return
	if player.vehicle != null:
		player.vehicle.call("exit_vehicle")
		await _frames(10)
	# Camera yaw -PI/2 makes "forward" point along +X in world space.
	player.world.rig.yaw = -PI / 2.0

	# ---- A) tall wall. Player feet at P, wall face 0.4 m in front (+X), spanning Y 370..430.
	var pa := Vector3(0.0, 400.0, 0.0)
	var tall := _wall(Vector3(0.9, 400.0, 0.0), Vector3(1.0, 60.0, 20.0))
	await _frames(4)
	await _place(pa)
	Input.action_press("forward")
	await _frames(40)
	check(player.climbing, "pressing into a tall wall in the air latches on")
	var y_latched: float = player.global_position.y
	var stamina_latched: float = player.climb_stamina
	await _frames(40)
	var y_climbed: float = player.global_position.y
	check(player.climbing, "still climbing a tall wall (no mantle yet)")
	check(y_climbed > y_latched + 1.0, "forward climbs the wall (%.1f -> %.1f m)" % [y_latched, y_climbed])
	check(player.climb_stamina < stamina_latched, "grip stamina drains while climbing (%.2f)" % player.climb_stamina)
	Input.action_release("forward")
	await _frames(2)
	var x_before_jump: float = player.global_position.x
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await _frames(12)
	check(not player.climbing, "jump lets go of the wall")
	check(player.global_position.x < x_before_jump - 0.5, "wall-jump pushes away from the wall (x %.2f -> %.2f)" % [x_before_jump, player.global_position.x])
	tall.queue_free()
	await _frames(60)  # let the player drop clear before the next case

	# ---- B) low ledge: top at P.y + 2 m. Climbing into it should mantle onto the top.
	var pb := Vector3(0.0, 400.0, 40.0)
	var ledge := _wall(Vector3(0.9, 399.0, 40.0), Vector3(1.0, 6.0, 20.0))
	await _frames(4)
	await _place(pb)
	Input.action_press("forward")
	for i in 60:  # release as soon as the player is on top; holding on walks them off the 1 m ledge
		await physics_frame
		if player.global_position.y > pb.y + 1.8:
			break
	Input.action_release("forward")
	await _frames(30)
	var y_top: float = player.global_position.y
	check(y_top > pb.y + 1.8, "climbing a low ledge mantles onto its top (y %.2f)" % y_top)
	check(player.is_on_floor(), "player stands on the ledge after mantling")
	check(not player.climbing, "mantle ends the climb")
	ledge.queue_free()

	print("RESULT: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
