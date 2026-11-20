extends SceneTree

## Rendered, player-eye verification of the living Sydney simulation.
## Run WINDOWED (no --headless). Captures are saved under tests/living_world_*.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var scene: Node3D
var player: Node3D
var rig: Node3D
var time_mgr: Node
var sim: Node
var building_boxes: Array = []


func _init() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	await _frames(30)
	player = scene.get("player")
	# The canonical opening starts in a car on the bridge; leave it so camera
	# viewpoints follow the on-foot player rather than the parked vehicle.
	if player != null and player.get("vehicle") != null:
		var car = player.get("vehicle")
		car.set("driver", null)
		player.set("vehicle", null)
		player.visible = true
		player.collision_layer = 1
		player.collision_mask = 1
		var camera_rig: Node = scene.get("BoomCamera")
		if camera_rig != null and camera_rig.get("arm") != null:
			camera_rig.get("arm").call("remove_excluded_object", car.get_rid())
	rig = scene.get("BoomCamera")
	time_mgr = scene.get_node_or_null("WorldTimeManager")
	sim = scene.get_node_or_null("WorldSimulationDirector")

	_index_buildings()
	var george_view: Dictionary = {}
	if scene.get("cbd_world") != null:
		george_view = scene.get("cbd_world").get("viewpoints").get("george_street", {})
	var george := Vector3(
		float(george_view.get("x", -110.0)), 0.35,
		float(george_view.get("z", 70.0))
	)
	var park := _walk_point(Vector2(270.0, -230.0))
	var quay := _walk_point(Vector2(220.0, -1450.0))
	var cross := _walk_point(Vector2(1500.0, 70.0))
	var harbour := _walk_point(Vector2(-600.0, -380.0))

	# Warm up the spring arm after leaving the car; the first teleport otherwise
	# resolves its collision one frame late and can push the camera into a wall.
	player.global_position = george
	await _frames(40)

	var g_yaw := _open_bearing(george.x, george.z)
	var george_dir := Vector3(-sin(g_yaw), 0.0, -cos(g_yaw))
	await _view("cbd_morning_commute", 8.0, george, george + george_dir * 100.0 + Vector3.UP * 1.5, 150, "clear")
	await _view("cbd_daytime_traffic", 12.5, george, george + george_dir * 130.0 + Vector3.UP * 2.0, 150, "clear")
	await _view("hyde_park_daytime", 14.0, park, Vector3(270.0, 9.0, -300.0), 140, "clear")
	await _view("circular_quay_tourists", 11.0, quay, Vector3(632.0, 18.0, -1650.0), 150, "clear")
	await _view("kings_cross_nightlife", 22.5, cross, cross + Vector3(18.0, 2.0, -70.0), 170, "clear")
	await _view("darling_harbour_evening", 19.0, harbour, Vector3(-660.0, 2.0, -420.0), 150, "clear")
	await _view("rainy_cbd_street", 12.0, george, george + george_dir * 90.0 + Vector3.UP * 2.0, 150, "heavy_rain")
	await _view("emergency_response", 21.5, george, george + george_dir * 110.0 + Vector3.UP * 2.0, 160, "clear", true)
	# Elevated, long-settled overview: makes the moving population countable.
	await _view("cbd_aerial_traffic", 12.5, Vector3(-40.0, 95.0, -380.0), Vector3(-110.0, 0.0, -520.0), 420, "clear")

	print("ALL LIVING WORLD CAPTURES COMPLETE")
	quit(0)


func _walk_point(target: Vector2) -> Vector3:
	var peds = scene.get_node_or_null("PedestrianManager")
	if peds == null or not ("graph_nodes" in peds):
		return Vector3(target.x, 0.4, target.y)
	var graph: Dictionary = peds.get("graph_nodes")
	var best := Vector2.ZERO
	var best_dist := INF
	for nid in graph:
		var node: Dictionary = graph[nid]
		var point := Vector2(float(node.get("x", 0.0)), float(node.get("z", 0.0)))
		var d := point.distance_squared_to(target)
		if d < best_dist:
			best_dist = d
			best = point
	return Vector3(best.x, 0.35, best.y)


## Building footprints and open-bearing framing, adapted from tests/cbd_visual.gd
## so a street-level capture looks along the road corridor instead of a wall.
func _index_buildings() -> void:
	building_boxes.clear()
	var world = scene.get("cbd_world")
	if world == null or not ("data" in world):
		return
	for row in world.get("data").get("buildings", []):
		var ring: Array = row.get("ring", [])
		if ring.size() < 3:
			continue
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for point in ring:
			var p := Vector2(float(point[0]), float(point[1]))
			low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
			high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
		building_boxes.append([low.x, low.y, high.x, high.y])


func _blocked(x: float, z: float) -> bool:
	for box in building_boxes:
		if x >= box[0] and x <= box[2] and z >= box[1] and z <= box[3]:
			return true
	return false


func _open_bearing(x: float, z: float) -> float:
	var best_yaw := 0.0
	var best_open := -1.0
	for step in 36:
		var yaw := TAU * float(step) / 36.0
		var forward := Vector2(-sin(yaw), -cos(yaw))
		var open := 175.0
		var travelled := 1.0
		while travelled < 175.0:
			if _blocked(x + forward.x * travelled, z + forward.y * travelled):
				open = travelled
				break
			travelled += 2.0 if travelled < 12.0 else 5.0
		if open > best_open:
			best_open = open
			best_yaw = yaw
	return best_yaw


func _view(
	name: String,
	hour: float,
	position: Vector3,
	look_at: Vector3,
	frames: int,
	weather: String,
	with_incident: bool = false
) -> void:
	if time_mgr != null and time_mgr.has_method("set_time"):
		time_mgr.call("set_time", hour)
	if sim != null:
		sim.call("set_weather", weather)
	if player != null:
		player.global_position = position
		player.velocity = Vector3.ZERO
	if rig != null:
		var forward := look_at - position
		rig.set("yaw", atan2(-forward.x, -forward.z))
		rig.set("pitch", clampf(atan2(forward.y, Vector2(forward.x, forward.z).length()), -0.6, 0.5))
	# Let traffic, pedestrians, venues and weather reach a steady state.
	await _frames(frames)
	if with_incident and sim != null:
		var incidents := scene.get_node_or_null("EmergencyIncidentManager")
		if incidents != null and incidents.has_method("request_police_response"):
			incidents.call("request_police_response", position + Vector3(-70.0, 0.0, -60.0), 1.5)
		await _frames(70)
	_save("res://tests/living_world_%s.png" % name)


func _save(path: String) -> void:
	var vp := get_root().get_viewport()
	var img := vp.get_texture().get_image()
	if img != null:
		img.save_png(ProjectSettings.globalize_path(path))
		print("SAVED %s" % path)
