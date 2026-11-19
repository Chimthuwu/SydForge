extends SceneTree

## Launches the real Sydney playtest scene (res://sydney/sydney_test.tscn) the
## same way F6 does, checks the existing player/camera/HUD/landmark, then saves
## two rendered views.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tests/sydney_playtest_test.gd

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


func _capture(path: String, label: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURED: ", label, " -> ", path)


func run() -> void:
	var world: Node3D = load("res://sydney/sydney_test.tscn").instantiate()
	root.add_child(world)
	for i in 90:
		await physics_frame

	check(world.using_sydney, "the playtest scene loads the Sydney world")
	check(world.sydney_world != null, "SydneyWorld is attached")
	check(world.player != null, "the existing player exists")
	check(world.rig != null and world.rig.camera != null, "the existing camera rig exists")
	check(world.rig.camera.current, "the camera is the active camera")
	check(world.hud != null and world.hud.text.contains("HEALTH"), "the existing HUD is running")
	check(world.vehicles.size() == 4, "the existing vehicles spawned")
	check(world.enemy != null, "the existing enemy spawned")

	var spawn: Vector3 = world.player.spawn
	var position: Vector3 = world.player.global_position
	check(position.distance_to(spawn) < 3.0,
		"player starts at the playtest spawn (%.1f, %.2f, %.1f)" % [position.x, position.y, position.z])
	check(world.player.is_on_floor(), "player settles on Sydney ground")
	check(position.y > -1.0 and position.y < 3.0, "player did not fall through the world")

	# The spawn must still be clear of water and buildings after a data change.
	var spawn_xz := Vector2(spawn.x, spawn.z)
	var in_water := false
	for ring in world.sydney_world.data.get("water", {}).get("rings", []):
		var polygon := PackedVector2Array()
		for point in ring:
			polygon.append(Vector2(float(point[0]), float(point[1])))
		if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(spawn_xz, polygon):
			in_water = true
			break
	check(not in_water, "playtest spawn is on land, not in the harbour")
	var clear_of_buildings := true
	for row in world.sydney_world.data.get("buildings", []):
		var ring: Array = row.get("ring", [])
		if ring.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for point in ring:
			polygon.append(Vector2(float(point[0]), float(point[1])))
		if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(spawn_xz, polygon):
			clear_of_buildings = false
			break
	check(clear_of_buildings, "playtest spawn is not inside a building")

	var opera: Node = world.sydney_world.get_node_or_null("OperaHouse")
	check(opera != null, "the Opera House landmark is in the playtest scene")
	if opera != null:
		check(opera.visible, "the Opera House is visible")
		var distance := Vector2(position.x + 0.0, position.z).distance_to(Vector2(658.72, -1763.81))
		check(distance < 600.0, "spawn is %.0f m from the Opera House, across the cove" % distance)
		check(opera.get_node_or_null("OperaCollision") != null, "the Opera House has collision")

	check(world.sydney_world.get_node_or_null("BuildingCollision") != null,
		"existing building collision is present")
	check(world.sydney_world.get_node_or_null("GroundCollision") != null,
		"existing ground collision is present")

	await _capture("res://tests/sydney_playtest_spawn.png", "playtest spawn view")

	# Movement through the existing controller (no test-only player).
	var start: Vector3 = world.player.global_position
	Input.action_press("forward")
	for i in 45:
		await physics_frame
	Input.action_release("forward")
	check(start.distance_to(world.player.global_position) > 1.0, "player walks with the existing controller")

	# The camera must follow the player.
	check(world.rig.global_position.distance_to(world.player.global_position) < 12.0,
		"camera follows the player")

	# Jump onto the Opera House podium deck and look at the shells.
	world.player.global_position = Vector3(642.6, 12.4, -1695.7)
	world.player.velocity = Vector3.ZERO
	world.rig.yaw = -0.03
	world.rig.pitch = -0.05
	for i in 40:
		await physics_frame
	check(world.player.global_position.y > 11.0, "player stands on the Opera House podium deck")
	await _capture("res://tests/sydney_playtest_opera.png", "on the Opera House podium")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
