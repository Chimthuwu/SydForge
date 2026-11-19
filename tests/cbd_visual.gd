extends SceneTree

## Phase 6B rendered captures. Windowed, not headless, because it saves renders:
##   Godot_v4.7.2-stable_win64_console.exe --path . \
##     --script res://tests/cbd_visual.gd --log-file tests/cbd_visual.log
##
## Loads the real `sydney/sydney_cbd_test.tscn` game scene (so the whole world,
## player, camera, HUD, vehicles and landmarks are the shipping ones), then adds
## one dedicated review camera and captures the district views named in the
## Phase 6B brief.

var scene: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("run")


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _capture(path: String, label: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURED: ", label, " -> ", path)


func _look(from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	if from.distance_to(at) > 0.1:
		camera.look_at(at, Vector3.UP)


func _forward(x: float, z: float, yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw)) + Vector3(x, 0.0, z)


func _viewpoint(id: String) -> Dictionary:
	return scene.cbd_world.viewpoints.get(id, {})


func _centre(id: String) -> Vector3:
	var row: Dictionary = scene.cbd_world.district_centres.get(id, {})
	if row.is_empty():
		return Vector3.ZERO
	return Vector3(float(row["x"]), 0.0, float(row["z"]))


## Building footprints as boxes, for open-sightline framing. Built once: walking
## the export per view would be slow and the boxes are enough to reject a
## camera bearing that would stare into a wall.
var building_boxes: Array = []


func _index_buildings() -> void:
	for row in scene.sydney_world.data.get("buildings", []):
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


## The most open bearing from a point: the direction whose sightline stays clear
## longest. This is what stops a district view from being a close-up of the
## nearest terrace wall, which is what a raw road bearing can produce at a bend.
func _open_bearing(x: float, z: float) -> float:
	var best_yaw := 0.0
	var best_open := -1.0
	for step in 36:
		var yaw := TAU * float(step) / 36.0
		var forward := Vector2(-sin(yaw), -cos(yaw))
		var open := 175.0
		# Start at 1 m: a wall two metres in front of the lens fills the frame
		# just as completely as one twenty metres away, and the first version
		# began sampling at 6 m, which is why some views were a close-up of a
		# neighbouring facade.
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


## Street-level view from an exported viewpoint, framed down the most open road
## corridor so the shot always has actual street in it.
func _street(id: String, distance: float = 130.0, target_height: float = 9.0) -> void:
	var view := _viewpoint(id)
	var x := float(view.get("x", 0.0))
	var z := float(view.get("z", 0.0))
	var yaw := _open_bearing(x, z)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye := Vector3(x, 2.9, z)
	_look(eye, eye + forward * distance + Vector3(0.0, target_height, 0.0))
	print("VIEW %s: yaw %.2f rad" % [id, yaw])


func run() -> void:
	scene = load("res://sydney/sydney_cbd_test.tscn").instantiate()
	root.add_child(scene)
	await _settle(10)
	# The scene builds its world in _ready; give the engine a few frames to
	# upload the (large) building mesh before the first capture.
	await _settle(40)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.far = 9000.0
	camera.near = 0.2
	scene.add_child(camera)
	camera.current = true
	await _settle(4)

	_index_buildings()
	print("WORLD BUILD TIMES (ms): ", scene.sydney_world.build_times_ms)
	print("BUILDING COUNTS: ", scene.sydney_world.geometry_counts.get("Buildings", {}))
	print("VEGETATION: ", scene.sydney_world.geometry_counts.get("Vegetation", {}))
	print("CONNECTIVITY: ", scene.sydney_world.stats)

	# 1. CBD aerial. South-east of the core, looking north-west across the
	#    George/Pitt grid toward Circular Quay and the Harbour Bridge.
	_look(Vector3(700.0, 430.0, 760.0), Vector3(-160.0, -30.0, -1000.0))
	await _capture("res://tests/cbd_aerial.png", "CBD aerial")

	# 1b. Second aerial over The Rocks and the quay, so the harbour edge and the
	#     two authored landmarks are both visible.
	_look(Vector3(-560.0, 330.0, -760.0), Vector3(360.0, -10.0, -1780.0))
	await _capture("res://tests/cbd_aerial_north.png", "CBD aerial, northern districts")

	# 2. Circular Quay promenade, looking east across the cove at the Opera
	#    House. The camera is the existing Phase 4 playtest spawn, so this view is
	#    reproducible by standing there in the game.
	_look(Vector3(219.9, 3.2, -1755.7), Vector3(658.7, 26.0, -1763.8))
	await _capture("res://tests/cbd_circular_quay.png", "Circular Quay toward the Opera House")

	# 2b. Opera House from its own forecourt, the visual-quality benchmark.
	_look(Vector3(632.1, 3.4, -1650.9), Vector3(658.7, 34.0, -1800.0))
	await _capture("res://tests/cbd_opera_forecourt.png", "Opera House from the forecourt")

	# 3. The Rocks: historic low-scale streetscape.
	_street("the_rocks", 110.0, 7.0)
	await _capture("res://tests/cbd_the_rocks.png", "The Rocks")

	# 4. George Street, looking along the street rather than across it: aiming at
	#    a distant landmark cut through the near building at this point of the
	#    street, which is why this view is framed down the road corridor.
	_street("george_street", 170.0, 14.0)
	await _capture("res://tests/cbd_george_street.png", "George Street")

	# 5. Wynyard, mid-town commercial.
	_street("wynyard", 120.0, 12.0)
	await _capture("res://tests/cbd_wynyard.png", "Wynyard")

	# 6. Town Hall.
	_street("town_hall", 120.0, 11.0)
	await _capture("res://tests/cbd_town_hall.png", "Town Hall")

	# 7. Chinatown / Haymarket.
	_street("chinatown", 100.0, 7.0)
	await _capture("res://tests/cbd_chinatown.png", "Chinatown and Haymarket")

	# 8. Central Station approach.
	_street("central", 130.0, 10.0)
	await _capture("res://tests/cbd_central.png", "Central Station")

	# 9. Surry Hills terraces.
	_street("surry_hills", 110.0, 6.0)
	await _capture("res://tests/cbd_surry_hills.png", "Surry Hills terraces")

	# 10-13. Remaining briefed districts.
	_street("darlinghurst", 110.0, 6.0)
	await _capture("res://tests/cbd_darlinghurst.png", "Darlinghurst")
	_street("kings_cross", 110.0, 8.0)
	await _capture("res://tests/cbd_kings_cross.png", "Kings Cross")
	_street("woolloomooloo", 110.0, 7.0)
	await _capture("res://tests/cbd_woolloomooloo.png", "Woolloomooloo")
	_street("barangaroo", 130.0, 14.0)
	await _capture("res://tests/cbd_barangaroo.png", "Barangaroo")

	# 14. Hyde Park and the eastern park edge.
	_look(Vector3(448.5, 90.0, -331.6 + 260.0), Vector3(470.0, 0.0, -560.0))
	await _capture("res://tests/cbd_hyde_park.png", "Hyde Park")

	scene.queue_free()
	await process_frame
	quit()
