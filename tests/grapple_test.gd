extends SceneTree

## Grappling hook checks (ported from SKYJUMP3D): firing hits what the camera looks
## at, holding reels the player toward the anchor, releasing lets go keeping speed,
## and jump cuts the rope.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://tests/grapple_test.gd

var checks := 0
var failures := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _initialize() -> void:
	call_deferred("run")


func _settle(frame_count: int) -> void:
	for i in frame_count:
		await physics_frame


func run() -> void:
	var opera: Node3D = load("res://sydney/sydney_opera_test.tscn").instantiate()
	root.add_child(opera)
	await _settle(160)
	var player: BoomPlayer = opera.player
	player.global_position = player.global_position + Vector3(0, 6.0, 0)
	player.velocity = Vector3.ZERO
	await _settle(20)

	# A solid wall 18 m in front of the camera, well above the ground.
	var camera: Camera3D = player.world.rig.camera
	var forward := -camera.global_basis.z
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 1)
	shape.shape = box
	wall.add_child(shape)
	wall.position = camera.global_position + forward * 18.0
	root.add_child(wall)
	wall.look_at(camera.global_position, Vector3.UP)
	await _settle(4)

	# ---- Fire at the wall.
	player.grapple_cd = 0.0
	player.grapple_fire()
	check(player.grapple_on, "firing at a solid surface attaches the grapple")
	var anchor_dist := (player.grapple_point - camera.global_position).length()
	check(absf(anchor_dist - 18.0) < 1.5, "anchor lands on the wall (%.1f m)" % anchor_dist)

	# ---- Hold to reel in: distance to anchor shrinks and the rope is visible.
	Input.action_press("grapple")
	var start_dist := (player.grapple_point - (player.global_position + Vector3(0, 1.2, 0))).length()
	var max_speed := 0.0
	for i in 30:
		await physics_frame
		max_speed = maxf(max_speed, player.velocity.length())
	var end_dist := (player.grapple_point - (player.global_position + Vector3(0, 1.2, 0))).length()
	check(player.grapple_on, "holding grapple keeps the rope attached")
	check(end_dist < start_dist - 1.0, "holding reels the player in (%.1f -> %.1f m)" % [start_dist, end_dist])
	check(max_speed > 5.0, "reeling builds speed (peak %.1f m/s)" % max_speed)
	check(player.grapple_rope != null and player.grapple_rope.visible, "rope is drawn while attached")

	# ---- Release: lets go, keeps speed.
	var speed_before := player.velocity.length()
	Input.action_release("grapple")
	await physics_frame
	check(not player.grapple_on, "releasing grapple detaches the rope")
	check(player.velocity.length() > speed_before * 0.5, "release keeps momentum (%.1f -> %.1f m/s)" % [speed_before, player.velocity.length()])

	# ---- Jump cuts the rope.
	await _settle(20)
	player.grapple_cd = 0.0
	player.global_position = camera.global_position - forward * 2.0
	player.velocity = Vector3.ZERO
	await _settle(4)
	player.grapple_fire()
	Input.action_press("grapple")
	await physics_frame
	check(player.grapple_on, "second fire attaches again")
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	check(not player.grapple_on, "jump cuts the rope")
	Input.action_release("grapple")

	# ---- Cooldown blocks an immediate refire.
	player.grapple_fire()
	check(not player.grapple_on or player.grapple_cd > 0.0, "fire is blocked by cooldown after a release")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	opera.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
