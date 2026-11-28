extends SceneTree

## Speed FX in the real game: driving fast with no boost must not trigger the NOS
## distortion or the speed FOV kick. Boost (holding sprint) must trigger both.
## Saves screenshots of each case to the scratchpad for visual review.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://tests/speed_fx_test.gd

const SHOT_DIR := "Z:/Temp/claude/6242974bc44eec45/cd41d2d9-f6b2-4436-9817-f786cdb0bee3/scratchpad"

var checks := 0
var failures := 0
var scene: Node3D


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
		await process_frame


func _shot(name: String) -> void:
	var img := get_root().get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/speed_fx_%s.png" % [SHOT_DIR, name])


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	var player = scene.get_node_or_null("Player")
	if player == null:
		var found := get_nodes_in_group("player")
		player = found[0] if not found.is_empty() else null
	check(player != null, "player resolved")
	if player == null:
		quit(1)
		return
	if player.get("vehicle") != null:
		player.get("vehicle").call("exit_vehicle")
		await _frames(10)

	var vehicles: Array = scene.get("vehicles") if "vehicles" in scene else []
	var bike = null
	for v in vehicles:
		if v != null and bool(v.get("is_motorbike")) and v.get("driver") == null and float(v.get("health")) > 0.0:
			bike = v
			break
	check(bike != null, "unoccupied motorbike found in the city")
	if bike == null:
		quit(1)
		return
	var entered: bool = bike.call("enter", player)
	check(entered, "player can get on the motorbike")
	await _frames(10)

	var camera: Camera3D = get_root().get_viewport().get_camera_3d()
	var overlay = scene.get_node_or_null("NOSOverlay")
	check(overlay != null, "NOS overlay present")

	# ---- Case 1: fast, no boost. Hold forward to keep speed up, sprint NOT held.
	Input.action_release("sprint")
	Input.action_press("forward")
	var peak_overlay := 0.0
	for i in 40:  # short run: a long straight at 30 m/s ends in a wreck
		bike.set("speed", maxf(float(bike.get("speed")), 30.0))
		await physics_frame
		peak_overlay = maxf(peak_overlay, float(overlay.get("current")))
	Input.action_release("forward")
	var speed_now := float(bike.get("speed"))
	var fov := camera.fov
	check(speed_now > 18.0, "bike is above the old 18 m/s trigger (%.1f m/s)" % speed_now)
	check(not bool(bike.get("boost_on")), "no boost is active")
	check(peak_overlay < 0.01, "NOS overlay stays off at speed without boost (peak %.3f)" % peak_overlay)
	check(fov < 69.5, "FOV does not widen from speed alone (%.1f deg)" % fov)
	_shot("fast_no_boost")

	# ---- Case 2: boost. Hold sprint + forward; overlay and boost FOV should react.
	# Case 1 can throw the rider off on a crash; get back on if so.
	if bike.get("driver") != player:
		bike.call("enter", player)
		await _frames(5)
	Input.action_press("sprint")
	Input.action_press("forward")
	await _frames(25)
	var boost_overlay := float(overlay.get("current"))
	var boost_fov := camera.fov
	check(bool(bike.get("boost_on")), "boost is active while sprint is held")
	check(boost_overlay > 0.2, "NOS overlay turns on while boosting (%.2f)" % boost_overlay)
	# The FOV eases in over a few frames; anything clearly above the 68 deg baseline counts.
	check(boost_fov > 68.3, "FOV widens while boosting (%.1f deg)" % boost_fov)
	_shot("boost")
	Input.action_release("sprint")
	Input.action_release("forward")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
