extends SceneTree

## Phase 4 visual captures. Windowed (not --headless), because it saves renders.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tests/sydney_phase4_visual.gd


func _initialize() -> void:
	call_deferred("run")


func _settle(frame_count: int) -> void:
	for i in frame_count:
		await physics_frame


func _capture(path: String, label: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURED: ", label, " -> ", path)


func _rings(world: Node3D) -> Array:
	return world.sydney_world.data.get("water", {}).get("rings", [])


func _nearest_shore(world: Node3D, from: Vector2) -> Vector2:
	var best := from
	var best_distance := INF
	for ring in _rings(world):
		var points: Array = ring
		for index in points.size():
			var a := Vector2(float(points[index][0]), float(points[index][1]))
			var next: Array = points[(index + 1) % points.size()]
			var b := Vector2(float(next[0]), float(next[1]))
			var closest := Geometry2D.get_closest_point_to_segment(from, a, b)
			if closest.distance_to(from) < best_distance:
				best_distance = closest.distance_to(from)
				best = closest
	return best


func _face(world: Node3D, target: Vector3) -> void:
	var forward: Vector3 = target - world.player.global_position
	forward.y = 0.0
	if forward.length() > 0.01:
		forward = forward.normalized()
		world.rig.yaw = atan2(-forward.x, -forward.z)


func _walk(frames: int) -> void:
	Input.action_press("forward")
	for i in frames:
		await physics_frame
	Input.action_release("forward")


func run() -> void:
	# 1. Circular Quay spawn.
	var quay: Node3D = load("res://sydney/sydney_test.tscn").instantiate()
	root.add_child(quay)
	await _settle(170)
	await _capture("res://tests/phase4_quay.png", "Circular Quay spawn")
	var times: Dictionary = quay.sydney_world.build_times_ms
	print("BUILD TIMES (ms): ", times)
	print("WATER COLLISION: ", quay.sydney_world.geometry_counts.get("WaterCollision", {}))

	# 2. Player standing at the harbour boundary.
	var spawn: Vector3 = quay.player.global_position
	var shore := _nearest_shore(quay, Vector2(spawn.x, spawn.z))
	var inland := (Vector2(spawn.x, spawn.z) - shore).normalized()
	var start := shore + inland * 3.0
	quay.player.global_position = Vector3(start.x, 0.4, start.y)
	quay.player.velocity = Vector3.ZERO
	await _settle(25)
	_face(quay, Vector3(shore.x, 0.0, shore.y))
	await _walk(150)
	quay.rig.pitch = -0.28
	await _capture("res://tests/phase4_harbour.png", "player stopped at the harbour boundary")
	quay.queue_free()
	await process_frame

	# 3. Opera House forecourt spawn.
	var opera: Node3D = load("res://sydney/sydney_opera_test.tscn").instantiate()
	root.add_child(opera)
	await _settle(170)
	opera.rig.pitch = -0.16
	await _capture("res://tests/phase4_forecourt.png", "Opera House forecourt spawn")
	var spot: Vector3 = opera.player.global_position

	# 4. Partway up the steps.
	_face(opera, Vector3(658.72, 12.0, -1763.81))
	await _walk(120)
	opera.rig.pitch = -0.34
	await _capture("res://tests/phase4_steps.png", "climbing the Opera House steps")

	# 5. Standing on the podium deck.
	var frames := 0
	while opera.player.global_position.y < 11.5 and frames < 480:
		await _walk(15)
		frames += 15
	opera.rig.pitch = -0.02
	await _capture("res://tests/phase4_podium.png", "exploring the podium deck")
	print("PODIUM: y %.2f after %d extra frames, spawn %s" % [opera.player.global_position.y, frames, spot])

	opera.queue_free()
	await process_frame
	quit()
