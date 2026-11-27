extends SceneTree

## Double-jump glide checks (ported from SKYJUMP3D): holding jump after the double
## jump caps the fall speed and drains the glide meter; a single jump does not glide.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://tests/double_jump_glide_test.gd

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


func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)


func run() -> void:
	var opera: Node3D = load("res://sydney/sydney_opera_test.tscn").instantiate()
	root.add_child(opera)
	await _settle(160)
	var player: BoomPlayer = opera.player
	var spawn := player.global_position + Vector3(0, 0.3, 0)

	# ---- Case 1: single jump, hold jump while falling -> must NOT glide.
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	await _settle(30)
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	var min_vy_single := 0.0
	var glided_single := false
	for i in 90:
		await physics_frame
		min_vy_single = minf(min_vy_single, player.velocity.y)
		glided_single = glided_single or player.gliding
	Input.action_release("jump")
	check(not glided_single, "single jump never enters glide")
	check(min_vy_single < -3.5, "single jump falls faster than glide speed (min vy %.2f)" % min_vy_single)

	# ---- Case 2: jump, double jump mid-air, hold jump -> glides.
	await _settle(120)
	player.global_position = spawn
	player.velocity = Vector3.ZERO
	await _settle(30)
	player.glide_meter = 1.0
	await _tap("jump")
	await _settle(12)
	await _tap("jump")
	check(player.used_double_jump, "second jump in the air is recorded as the double jump")
	Input.action_press("jump")
	var min_vy_glide := 0.0
	var meter_start := player.glide_meter
	var glided := false
	for i in 90:
		await physics_frame
		if player.velocity.y < 0.5 and not player.is_on_floor():
			min_vy_glide = minf(min_vy_glide, player.velocity.y)
		glided = glided or player.gliding
	Input.action_release("jump")
	var meter_used := meter_start - player.glide_meter
	check(glided, "holding jump after double jump enters glide")
	check(min_vy_glide >= -3.01 and min_vy_glide < -2.5,
		"glide caps fall speed near -3.0 (min vy %.2f)" % min_vy_glide)
	check(meter_used > 0.0, "glide drains the meter (used %.3f)" % meter_used)

	# ---- Case 3: landing refills meter and clears the double-jump flag.
	await _settle(240)
	check(player.is_on_floor(), "player lands after glide")
	check(not player.used_double_jump, "landing clears the double-jump flag")
	check(player.glide_meter > meter_start - meter_used - 0.001 or player.glide_meter >= 0.99,
		"landing refills the glide meter (%.2f)" % player.glide_meter)

	print("RESULT: %d checks, %d failures" % [checks, failures])
	opera.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
