extends SceneTree

## Day/night visual review of the canonical game scene after the art pass.
## Windowed (it writes PNGs):
##   Godot_v4.7.2-stable_win64_console.exe --path . \
##     --script res://tests/overhaul_visual.gd --log-file tests/overhaul_visual.log

var scene: Node3D
var review: Camera3D
var buildings: Array = []


func _initialize() -> void:
	call_deferred("run")


func _settle(count: int) -> void:
	for i in count:
		await process_frame


func _capture(file: String, label: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("CAPTURED: ", label, " -> ", file)


func _look(from: Vector3, at: Vector3) -> void:
	review.global_position = from
	if from.distance_to(at) > 0.1:
		review.look_at(at, Vector3.UP)


func _index_buildings() -> void:
	for row in scene.cbd_world.data.get("buildings", []):
		var ring: Array = row.get("ring", [])
		if ring.size() < 3:
			continue
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for point in ring:
			var p := Vector2(float(point[0]), float(point[1]))
			low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
			high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
		buildings.append({"low": low, "high": high, "center": (low + high) * 0.5, "row": row})


func _blocked(x: float, z: float) -> bool:
	for box in buildings:
		var low: Vector2 = box["low"]
		var high: Vector2 = box["high"]
		if x >= low.x and x <= high.x and z >= low.y and z <= high.y:
			return true
	return false


func _open_bearing(x: float, z: float) -> float:
	var best_yaw := 0.0
	var best_open := -1.0
	for step in 48:
		var yaw := TAU * float(step) / 48.0
		var forward := Vector2(-sin(yaw), -cos(yaw))
		var open := 160.0
		var travelled := 2.0
		while travelled < 160.0:
			if _blocked(x + forward.x * travelled, z + forward.y * travelled):
				open = travelled
				break
			travelled += 2.0 if travelled < 12.0 else 4.0
		if open > best_open:
			best_open = open
			best_yaw = yaw
	return best_yaw


## Stand on an exported road centreline so the lens can never start inside a
## facade (the previous viewpoint-based shot clipped through a wall).
func _road_near(origin: Vector2, prefer: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for road in scene.cbd_world.data.get("roads", []):
		var points: Array = road.get("points", [])
		if points.size() < 3:
			continue
		var midpoint := Vector2(float(points[points.size() / 2][0]), float(points[points.size() / 2][1]))
		var score := origin.distance_to(midpoint)
		if not prefer.is_empty() and str(road.get("name", "")).to_lower().contains(prefer):
			score *= 0.35
		if str(road.get("highway", "")) in ["primary", "secondary", "trunk"]:
			score *= 0.85
		if score < best_score:
			best_score = score
			best = road
	return best


func _street_camera(id: String, distance: float, height: float) -> void:
	var view: Dictionary = scene.cbd_world.viewpoints.get(id, {})
	var origin := Vector2(float(view.get("x", 0.0)), float(view.get("z", 0.0)))
	var road := _road_near(origin, "george" if id == "george_street" else "")
	var points: Array = road.get("points", [])
	if points.size() < 3:
		_look(Vector3(origin.x, 2.7, origin.y), Vector3(origin.x, 10.0, origin.y - distance))
		return
	var index := points.size() / 2
	var point := Vector2(float(points[index][0]), float(points[index][1]))
	var before := Vector2(float(points[maxi(index - 1, 0)][0]), float(points[maxi(index - 1, 0)][1]))
	var after := Vector2(float(points[mini(index + 1, points.size() - 1)][0]), float(points[mini(index + 1, points.size() - 1)][1]))
	var tangent := (after - before).normalized()
	if tangent.length_squared() < 0.1:
		tangent = Vector2(0.0, -1.0)
	var eye := Vector3(point.x, 2.7, point.y)
	_look(eye, eye + Vector3(tangent.x, 0.0, tangent.y) * distance + Vector3(0.0, height, 0.0))


func _facade_camera(id: String) -> void:
	var view: Dictionary = scene.cbd_world.viewpoints.get(id, {})
	var origin := Vector2(float(view.get("x", 0.0)), float(view.get("z", 0.0)))
	var best: Dictionary = {}
	var best_distance := INF
	for box in buildings:
		var center: Vector2 = box["center"]
		var d := origin.distance_to(center)
		if d < 8.0 or d > 70.0:
			continue
		if d < best_distance:
			best_distance = d
			best = box
	if best.is_empty():
		return
	var center: Vector2 = best["center"]
	var direction := (origin - center).normalized()
	var distance := maxf(8.0, (best["high"] as Vector2).distance_to(center) + 11.0)
	var eye := Vector3(center.x + direction.x * distance, 7.5, center.y + direction.y * distance)
	_look(eye, Vector3(center.x, 12.0, center.y))


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(60)
	_index_buildings()
	var time_manager := scene.get_node_or_null("WorldTimeManager") as WorldTimeManager
	check_time_manager(time_manager)

	review = Camera3D.new()
	review.fov = 64.0
	review.far = 9000.0
	review.near = 0.2
	scene.add_child(review)
	review.current = true
	await _settle(6)

	# Daylight.
	time_manager.set_time(13.0)
	await _settle(45)
	_look(Vector3(700.0, 430.0, 760.0), Vector3(-160.0, -30.0, -1000.0))
	await _capture("res://tests/overhaul_day_aerial.png", "day aerial")
	_street_camera("george_street", 160.0, 12.0)
	await _capture("res://tests/overhaul_day_street.png", "day George Street")
	_facade_camera("george_street")
	await _capture("res://tests/overhaul_day_facade.png", "day facade close-up")
	_street_camera("surry_hills", 120.0, 7.0)
	await _capture("res://tests/overhaul_day_terraces.png", "day Surry Hills")
	_look(Vector3(219.9, 3.2, -1755.7), Vector3(658.7, 26.0, -1763.8))
	await _capture("res://tests/overhaul_day_quay.png", "day Circular Quay")

	# Night: same street, lit windows and readable road.
	time_manager.set_time(21.5)
	await _settle(45)
	_street_camera("george_street", 160.0, 12.0)
	await _capture("res://tests/overhaul_night_street.png", "night George Street")
	_look(Vector3(219.9, 3.2, -1755.7), Vector3(658.7, 26.0, -1763.8))
	await _capture("res://tests/overhaul_night_quay.png", "night Circular Quay")
	_look(Vector3(700.0, 430.0, 760.0), Vector3(-160.0, -30.0, -1000.0))
	await _capture("res://tests/overhaul_night_aerial.png", "night aerial")

	# First-person weapon presentation uses the shipping camera, in daylight.
	time_manager.set_time(13.0)
	await _settle(30)
	review.current = false
	scene.rig.camera.current = true
	await _settle(10)
	await _capture("res://tests/overhaul_first_person.png", "first-person pistol")

	print("AUDIO BUSES: ", AudioServer.bus_count)
	scene.queue_free()
	await process_frame
	quit()


func check_time_manager(time_manager: WorldTimeManager) -> void:
	if time_manager == null:
		push_error("No WorldTimeManager in main scene")
