extends SceneTree

## Phase 4 physical-playability checks, run against the real playtest scenes:
## harbour collision, step traversal up and down the Opera House podium, jump
## preservation, wall impassability and the forecourt entry point.
##
##   ./Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tests/sydney_physics_test.gd

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


func _rings(world: Node3D) -> Array:
	# Phase 6A: the harbour module's rings are the rendered water surface and
	# the barrier; the export's water rings remain the fallback if the module
	# is ever absent.
	var harbour: Node = world.sydney_world.get_node_or_null("HarbourWater")
	if harbour != null and not harbour.rings.is_empty():
		return harbour.rings
	return world.sydney_world.data.get("water", {}).get("rings", [])


func _polygons(world: Node3D) -> Array:
	var out: Array = []
	for ring in _rings(world):
		var polygon := PackedVector2Array()
		for point in ring:
			polygon.append(Vector2(float(point[0]), float(point[1])))
		if polygon.size() >= 3:
			out.append(polygon)
	return out


func _in_water(world: Node3D, point: Vector2) -> bool:
	for polygon in _polygons(world):
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


## Closest point on any water ring boundary to `from`. Handles both the
## harbour module's PackedVector2Array rings and the export's [x, z] arrays.
func _nearest_shore(world: Node3D, from: Vector2) -> Vector2:
	var best := from
	var best_distance := INF
	for ring in _rings(world):
		var count: int = ring.size()
		for index in count:
			var a := _ring_point(ring[index])
			var b := _ring_point(ring[(index + 1) % count])
			var closest := Geometry2D.get_closest_point_to_segment(from, a, b)
			var distance := closest.distance_to(from)
			if distance < best_distance:
				best_distance = distance
				best = closest
	return best


func _ring_point(item) -> Vector2:
	if typeof(item) == TYPE_VECTOR2:
		return item
	return Vector2(float(item[0]), float(item[1]))


func _distance_to_shore(world: Node3D, point: Vector2) -> float:
	return _nearest_shore(world, point).distance_to(point)


func _face(world: Node3D, target: Vector3) -> void:
	var forward: Vector3 = target - world.player.global_position
	forward.y = 0.0
	if forward.length() > 0.01:
		forward = forward.normalized()
		world.rig.yaw = atan2(-forward.x, -forward.z)


func _place(world: Node3D, position: Vector3) -> void:
	world.player.global_position = position
	world.player.velocity = Vector3.ZERO


func _walk(frames: int) -> void:
	Input.action_press("forward")
	for i in frames:
		await physics_frame
	Input.action_release("forward")


func _jump_forward(frames: int) -> void:
	Input.action_press("forward")
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	for i in frames - 2:
		await physics_frame
	Input.action_release("forward")


func run() -> void:
	# ------------------------------------------------------- Circular Quay -----
	var quay: Node3D = load("res://sydney/sydney_test.tscn").instantiate()
	root.add_child(quay)
	await _settle(160)

	check(quay.using_sydney, "Circular Quay playtest scene loads Sydney")
	check(quay.player is BoomPlayer, "Circular Quay scene uses the existing player")
	# Phase 6A: the harbour module owns the visual water and the shoreline
	# barrier (the Stage A Water mesh/WaterCollision are superseded by it).
	var harbour: Node = quay.sydney_world.get_node_or_null("HarbourWater")
	check(harbour != null, "harbour water module exists")
	var barrier: Node = harbour.get_node_or_null("HarbourWaterCollision") if harbour != null else null
	check(barrier != null, "harbour shoreline barrier exists")
	var stats: Dictionary = quay.sydney_world.geometry_counts.get("HarbourWater", {})
	check(int(stats.get("collisionRings", 0)) >= _rings(quay).size(),
		"harbour barrier covers every water ring (%d rings)" % int(stats.get("collisionRings", 0)))
	check(int(stats.get("collisionTriangles", 0)) > 0 and int(stats.get("collisionTriangles", 0)) < 24000,
		"harbour barrier is one light mesh (%d triangles)" % int(stats.get("collisionTriangles", 0)))

	var spawn: Vector3 = quay.player.global_position
	check(not _in_water(quay, Vector2(spawn.x, spawn.z)), "Circular Quay spawn is on land")

	# Start three metres inland of the nearest water edge and walk at it.
	var shore := _nearest_shore(quay, Vector2(spawn.x, spawn.z))
	var inland := (Vector2(spawn.x, spawn.z) - shore).normalized()
	var start := shore + inland * 3.0
	_place(quay, Vector3(start.x, 0.4, start.y))
	await _settle(25)
	check(not _in_water(quay, start), "water test start point is on land")
	_face(quay, Vector3(shore.x, 0.0, shore.y))
	await _walk(180)
	var stopped := Vector2(quay.player.global_position.x, quay.player.global_position.z)
	check(not _in_water(quay, stopped), "player cannot walk into Sydney Cove")
	check(_distance_to_shore(quay, stopped) < 2.0,
		"player stops at the rendered shoreline (%.2f m)" % _distance_to_shore(quay, stopped))
	check(quay.player.global_position.y > -0.5, "player stays on the quay surface")

	await _jump_forward(150)
	var jumped := Vector2(quay.player.global_position.x, quay.player.global_position.z)
	check(not _in_water(quay, jumped), "jumping cannot carry the player over the shoreline")
	check(quay.player.global_position.y > -0.5, "player lands back on the quay")

	# Ordinary movement away from the water still works.
	_place(quay, spawn)
	await _settle(25)
	var walk_start: Vector3 = quay.player.global_position
	_face(quay, walk_start + Vector3(0.0, 0.0, 30.0))
	await _walk(50)
	check(walk_start.distance_to(quay.player.global_position) > 1.5,
		"ordinary walking on land still works")

	quay.queue_free()
	await process_frame

	# ------------------------------------------------------ Opera forecourt ----
	var opera: Node3D = load("res://sydney/sydney_opera_test.tscn").instantiate()
	root.add_child(opera)
	await _settle(160)

	check(opera.using_sydney, "Opera House playtest scene loads Sydney")
	check(opera.player is BoomPlayer, "opera scene uses the existing player")
	var spot: Vector3 = opera.player.global_position
	check(not _in_water(opera, Vector2(spot.x, spot.z)), "forecourt spawn is on land")
	check(spot.distance_to(Vector3(658.72, spot.y, -1763.81)) < 130.0,
		"forecourt spawn is at Bennelong Point (%.0f m)" % spot.distance_to(Vector3(658.72, spot.y, -1763.81)))
	check(spot.y < 1.0, "forecourt spawn is at ground level (y %.2f)" % spot.y)
	check(opera.player.is_on_floor(), "forecourt spawn rests on the ground")
	var landmark: Node = opera.sydney_world.get_node_or_null("OperaHouse")
	check(landmark != null and landmark.visible, "Opera House is present and visible")
	if landmark != null:
		check(landmark.get_node_or_null("OperaCollision") != null, "Opera House collision is present")

	# Straight at the podium: 7 m of plaza, then 24 risers of 0.5 m.
	var base_y: float = spot.y
	_face(opera, Vector3(658.72, 12.0, -1763.81))
	await _walk(420)
	var top: Vector3 = opera.player.global_position
	check(top.y > 11.0, "player climbs all 24 podium risers without jumping (%.2f -> %.2f m)" % [base_y, top.y])
	check(top.y < 13.0, "player stands on the podium deck, not floating (%.2f m)" % top.y)
	check(not _in_water(opera, Vector2(top.x, top.z)), "podium deck is dry land")

	_face(opera, Vector3(spot.x, 0.0, spot.z))
	await _walk(420)
	var bottom: Vector3 = opera.player.global_position
	check(bottom.y < 1.0, "player walks back down the steps (%.2f m)" % bottom.y)
	check(opera.player.is_on_floor(), "player is on the forecourt after descending")

	# Jumping must still work from flat ground.
	_place(opera, Vector3(spot.x, 0.3, spot.z))
	await _settle(30)
	var floor_y: float = opera.player.global_position.y
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	var peak := floor_y
	for i in 60:
		await physics_frame
		peak = maxf(peak, opera.player.global_position.y)
	check(peak > floor_y + 1.0, "jumping still works (peak +%.2f m)" % (peak - floor_y))
	check(opera.player.is_on_floor(), "player is back on the ground after jumping")

	# A 31 m building wall must stay impassable for the step assist.
	_place(opera, Vector3(303.1, 0.3, -789.0))
	await _settle(30)
	var wall_start := Vector2(303.1, -789.0)
	_face(opera, Vector3(500.0, 0.0, -789.0))
	await _walk(180)
	var wall_pos := Vector2(opera.player.global_position.x, opera.player.global_position.z)
	check(opera.player.global_position.y < 2.0,
		"step assist cannot climb a building wall (y %.2f)" % opera.player.global_position.y)
	check(wall_pos.distance_to(wall_start) < 4.0,
		"player is stopped by the wall after %.1f m" % wall_pos.distance_to(wall_start))
	check(wall_pos.x < 310.0, "player did not pass through the building")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	opera.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
