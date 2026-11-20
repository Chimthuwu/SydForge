extends SceneTree

## World-quality review captures for the Sydney CBD scene.
## Windowed, writes PNGs:
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 \
##     --script res://tests/quality_views.gd
## Set SPLOOGE_SHOTS=quality_before (or any folder) to choose the output folder.

var scene: Node3D
var review: Camera3D
var shots := "quality_before"
var buildings: Array = []


func _initialize() -> void:
	var env := OS.get_environment("SPLOOGE_SHOTS")
	if not env.is_empty():
		shots = env
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/" + shots))
	call_deferred("run")


func _settle(count: int) -> void:
	for i in count:
		await process_frame


func _capture(file: String, label: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/%s/%s.png" % [shots, file])
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


## Pick the road nearest to a viewpoint, preferring a wide named arterial.
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
			score *= 0.3
		if str(road.get("highway", "")) in ["primary", "secondary", "trunk", "motorway"]:
			score *= 0.8
		if score < best_score:
			best_score = score
			best = road
	return best


## Eye-level shot down a road, centred on the carriageway.
func _street(id: String, prefer: String, height: float, distance: float, lateral: float = 0.0) -> Dictionary:
	var view: Dictionary = scene.cbd_world.viewpoints.get(id, {})
	var origin := Vector2(float(view.get("x", 0.0)), float(view.get("z", 0.0)))
	var road := _road_near(origin, prefer)
	var points: Array = road.get("points", [])
	if points.size() < 3:
		_look(Vector3(origin.x, height, origin.y), Vector3(origin.x, height + 4.0, origin.y - distance))
		return {}
	var index := points.size() / 2
	var point := Vector2(float(points[index][0]), float(points[index][1]))
	var before := Vector2(float(points[maxi(index - 2, 0)][0]), float(points[maxi(index - 2, 0)][1]))
	var after := Vector2(float(points[mini(index + 2, points.size() - 1)][0]), float(points[mini(index + 2, points.size() - 1)][1]))
	var tangent := (after - before).normalized()
	if tangent.length_squared() < 0.1:
		tangent = Vector2(0.0, -1.0)
	var side := Vector2(-tangent.y, tangent.x)
	var eye := Vector3(point.x + side.x * lateral, height, point.y + side.y * lateral)
	var target := eye + Vector3(tangent.x, 0.0, tangent.y) * distance + Vector3(0.0, -1.2, 0.0)
	_look(eye, target)
	return {"road": road, "point": point, "tangent": tangent, "side": side, "width": float(road.get("widthM", 8.0))}


func _facade(id: String) -> void:
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
	_look(Vector3(center.x + direction.x * distance, 7.5, center.y + direction.y * distance),
		Vector3(center.x, 12.0, center.y))


## Move the player (and therefore the actor spawn) to a street position, then
## place the camera next to the nearest pedestrian.
func _stand_at(x: float, z: float) -> void:
	var player = scene.player
	if player == null:
		return
	player.global_position = Vector3(x, 0.3, z)
	if player.vehicle != null:
		player.vehicle.global_position = Vector3(x, 0.5, z)
	await _settle(30)


func _pedestrian_shot(file: String, label: String, group: bool) -> void:
	var peds: Node = scene.get_node_or_null("PedestrianManager")
	if peds == null:
		return
	var list: Array = peds.get("active_pedestrians")
	if list.is_empty():
		print("NO PEDESTRIANS for ", file)
		return
	var target = null
	for candidate in list:
		if is_instance_valid(candidate):
			target = candidate
			break
	if target == null:
		return
	var pos: Vector3 = target.global_position
	var forward: Vector3 = -target.global_transform.basis.z
	var side := Vector3(-forward.z, 0.0, forward.x)
	if group:
		_look(pos + side * 4.2 - forward * 1.4 + Vector3.UP * 1.6, pos + Vector3.UP * 1.25)
	else:
		_look(pos + forward * 2.4 + side * 0.7 + Vector3.UP * 1.45, pos + Vector3.UP * 1.2)
	await _capture(file, label)


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(60)
	_index_buildings()
	var time_manager := scene.get_node_or_null("WorldTimeManager")
	if time_manager != null:
		time_manager.set_time(13.0)
	await _settle(30)

	review = Camera3D.new()
	review.fov = 62.0
	review.far = 9000.0
	review.near = 0.08
	scene.add_child(review)
	review.current = true
	await _settle(6)

	# 1. CBD street at eye level.
	var george := _street("george_street", "george", 1.75, 90.0)
	await _capture("01_cbd_street", "CBD street eye level")

	# 2/3/4. Road surface, kerb and footpath close-ups beside the same road.
	if not george.is_empty():
		var point: Vector2 = george["point"]
		var tangent: Vector2 = george["tangent"]
		var side: Vector2 = george["side"]
		var half: float = float(george["width"]) * 0.5
		var eye := Vector3(point.x, 1.35, point.y) - Vector3(tangent.x, 0.0, tangent.y) * 3.0
		_look(eye, Vector3(point.x, 0.0, point.y) + Vector3(tangent.x, 0.0, tangent.y) * 14.0)
		await _capture("02_asphalt_markings", "asphalt and markings")
		var kerb_eye := Vector3(point.x + side.x * (half - 1.0), 1.15, point.y + side.y * (half - 1.0))
		_look(kerb_eye, Vector3(point.x + side.x * (half + 1.5), 0.05, point.y + side.y * (half + 1.5)))
		await _capture("03_kerb_gutter", "kerb and gutter")
		var path_eye := Vector3(point.x + side.x * (half + 0.9), 1.62, point.y + side.y * (half + 0.9))
		_look(path_eye, Vector3(point.x + side.x * (half + 2.6), 0.0, point.y + side.y * (half + 2.6))
			+ Vector3(tangent.x, 0.0, tangent.y) * 10.0)
		await _capture("04_footpath", "footpath surface")

	# 5. Intersection.
	var junction := _nearest_junction(Vector2(george.get("point", Vector2(-100, 90))))
	if not junction.is_empty():
		var jc := Vector2(float(junction.get("x", 0.0)), float(junction.get("z", 0.0)))
		_look(Vector3(jc.x + 9.0, 7.0, jc.y + 9.0), Vector3(jc.x, 0.0, jc.y))
		await _capture("05_intersection", "four-way intersection")

	# 6. Curved road / corner.
	var curve := _curviest_road(Vector2(george.get("point", Vector2(-100, 90))))
	if not curve.is_empty():
		var cpts: Array = curve.get("points", [])
		var ci: int = cpts.size() / 2
		var cp := Vector2(float(cpts[ci][0]), float(cpts[ci][1]))
		var cb := Vector2(float(cpts[maxi(ci - 2, 0)][0]), float(cpts[maxi(ci - 2, 0)][1]))
		var ca := Vector2(float(cpts[mini(ci + 2, cpts.size() - 1)][0]), float(cpts[mini(ci + 2, cpts.size() - 1)][1]))
		var ct := (ca - cb).normalized()
		var cs := Vector2(-ct.y, ct.x)
		_look(Vector3(cp.x - cs.x * 5.0, 9.0, cp.y - cs.y * 5.0), Vector3(cp.x, 0.0, cp.y))
		await _capture("06_curved_road", "curved road and corner")

	# 7/8. Residential and commercial.
	_street("surry_hills", "", 1.7, 70.0, 1.5)
	await _capture("07_residential", "residential street")
	_street("george_street", "pitt", 1.7, 70.0, -1.5)
	await _capture("08_commercial", "commercial street")

	# 9/10/11. Pedestrians: move to the CBD footpath so pedestrians spawn there.
	await _stand_at(float(george.get("point", Vector2(-100, 90)).x) + 8.0, float(george.get("point", Vector2(-100, 90)).y))
	await _settle(120)
	await _pedestrian_shot("09_pedestrian_closeup", "pedestrian close-up", false)
	await _pedestrian_shot("10_pedestrian_group", "pedestrian group", true)
	_look(Vector3(float(george.get("point", Vector2(-100, 90)).x), 6.0, float(george.get("point", Vector2(-100, 90)).y) + 12.0),
		Vector3(float(george.get("point", Vector2(-100, 90)).x), 1.0, float(george.get("point", Vector2(-100, 90)).y) - 14.0))
	await _capture("11_pedestrians_walking", "pedestrians walking")

	# 12. CBD skyline.
	_look(Vector3(700.0, 430.0, 760.0), Vector3(-160.0, -30.0, -1000.0))
	await _capture("12_cbd_skyline", "CBD skyline")

	# 13/14. Circular Quay and Darling Harbour.
	_look(Vector3(219.9, 3.2, -1755.7), Vector3(658.7, 26.0, -1763.8))
	await _capture("13_circular_quay", "Circular Quay")
	var darling := _viewpoint_or("darling_harbour", Vector3(-500.0, 4.0, -900.0))
	_look(darling + Vector3.UP * 3.0, darling + Vector3(1.0, 2.0, -1.0) * 80.0)
	await _capture("14_darling_harbour", "Darling Harbour")

	# 15. Night street.
	time_manager.set_time(21.0)
	await _settle(45)
	_street("george_street", "george", 1.75, 80.0)
	await _capture("15_night_street", "night street")

	scene.queue_free()
	await process_frame
	quit()


func _viewpoint_or(id: String, fallback: Vector3) -> Vector3:
	var view: Dictionary = scene.cbd_world.viewpoints.get(id, {})
	if view.is_empty():
		return fallback
	return Vector3(float(view.get("x", fallback.x)), fallback.y, float(view.get("z", fallback.z)))


func _nearest_junction(origin: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for junction in scene.cbd_world.data.get("junctions", []):
		if int(junction.get("roadCount", 0)) < 4:
			continue
		var point := Vector2(float(junction.get("x", 0.0)), float(junction.get("z", 0.0)))
		var distance := point.distance_to(origin)
		if distance < best_distance:
			best_distance = distance
			best = junction
	return best


func _curviest_road(origin: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for road in scene.cbd_world.data.get("roads", []):
		var points: Array = road.get("points", [])
		if points.size() < 5 or bool(road.get("tunnel", false)):
			continue
		var midpoint := Vector2(float(points[points.size() / 2][0]), float(points[points.size() / 2][1]))
		if midpoint.distance_to(origin) > 900.0:
			continue
		var turn := 0.0
		for index in range(1, points.size() - 1):
			var a := Vector2(float(points[index - 1][0]), float(points[index - 1][1]))
			var b := Vector2(float(points[index][0]), float(points[index][1]))
			var c := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
			turn += absf((b - a).angle_to(c - b))
		var score := turn - midpoint.distance_to(origin) / 900.0
		if score > best_score:
			best_score = score
			best = road
	return best
