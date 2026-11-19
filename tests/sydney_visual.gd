extends SceneTree

## Windowed capture of the Stage A Sydney world.
## Run with SPLOOGE_SYDNEY=1 so district.gd takes the Sydney path:
##   Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/sydney_visual.gd

func _initialize() -> void:
	call_deferred("run")


func _capture(camera: Camera3D, path: String, label: String) -> void:
	camera.current = true
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("VISUAL captured: ", label, " -> ", path)


func _find_bend(roads: Array) -> Dictionary:
	var best := {"angle": 0.0}
	for road in roads:
		if bool(road.get("tunnel", false)):
			continue
		var points: Array = road.get("points", [])
		for index in range(1, points.size() - 1):
			var a := Vector2(float(points[index - 1][0]), float(points[index - 1][1]))
			var b := Vector2(float(points[index][0]), float(points[index][1]))
			var c := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
			var incoming := (b - a)
			var outgoing := (c - b)
			if incoming.length() < 1.0 or outgoing.length() < 1.0:
				continue
			var angle := absf(incoming.normalized().angle_to(outgoing.normalized()))
			# Prefer a street-scale bend rather than a kerb-size wiggle or a
			# 150-degree hairpin hidden behind buildings.
			if angle < 0.6 or angle > 1.8:
				continue
			if angle > float(best["angle"]):
				best = {"angle": angle, "point": b, "direction": incoming.normalized(), "road": road.get("name", "")}
	return best


func _find_junction(junctions: Array, spawn: Vector3) -> Dictionary:
	var best := {}
	var best_score := INF
	for junction in junctions:
		var degree := int(junction.get("roadCount", 0))
		if degree < 4:
			continue
		var distance := Vector2(float(junction["x"]) - spawn.x, float(junction["z"]) - spawn.z).length()
		var score := distance - float(degree) * 20.0
		if score < best_score:
			best_score = score
			best = junction
	return best


func _find_concave_building(buildings: Array) -> Dictionary:
	var best := {}
	var best_area := 0.0
	for building in buildings:
		var ring: Array = building.get("ring", [])
		if ring.size() < 5:
			continue
		var signs := []
		for index in ring.size():
			var a := Vector2(float(ring[index - 1][0]), float(ring[index - 1][1]))
			var b := Vector2(float(ring[index][0]), float(ring[index][1]))
			var c := Vector2(float(ring[(index + 1) % ring.size()][0]), float(ring[(index + 1) % ring.size()][1]))
			var value := (b - a).cross(c - b)
			if absf(value) > 0.001:
				signs.append(signf(value))
		if signs.has(1.0) and signs.has(-1.0):
			var area := float(building.get("areaM2", 0.0))
			if area > best_area:
				best_area = area
				best = building
	return best


func run() -> void:
	var world: Node3D = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	for i in 90:
		await process_frame
	print("VISUAL using_sydney: ", world.using_sydney)
	print("VISUAL spawn: ", world.player.spawn)
	print("VISUAL stats: ", world.sydney_world.stats)
	print("VISUAL geometry_counts: ", world.sydney_world.geometry_counts)
	print("VISUAL build_times_ms: ", world.sydney_world.build_times_ms)
	var spawn: Vector3 = world.player.spawn

	world.rig.set_process(false)
	var aerial := Camera3D.new()
	world.add_child(aerial)
	aerial.global_position = spawn + Vector3(420, 430, 520)
	aerial.look_at(spawn + Vector3(-40, 0, -180))
	aerial.far = 4000.0
	await _capture(aerial, "res://tests/sydney_overview.png", "aerial CBD")

	var street := Camera3D.new()
	world.add_child(street)
	street.global_position = spawn + Vector3(0, 1.75, 0)
	street.rotation.y = world.sydney_world.player_yaw
	street.far = 4000.0
	await _capture(street, "res://tests/sydney_street.png", "street level")

	var quay := Camera3D.new()
	world.add_child(quay)
	quay.global_position = Vector3(300, 90, -1650)
	quay.look_at(Vector3(-150, 0, -1200))
	quay.far = 4000.0
	await _capture(quay, "res://tests/sydney_circular_quay.png", "Circular Quay")

	var data: Dictionary = world.sydney_world.data
	var bend := _find_bend(data.get("roads", []))
	if not bend.is_empty():
		var point: Vector2 = bend["point"]
		var direction: Vector2 = bend["direction"]
		var bend_camera := Camera3D.new()
		world.add_child(bend_camera)
		bend_camera.global_position = Vector3(point.x, 0, point.y) - Vector3(direction.x, 0, direction.y) * 38.0 + Vector3(0, 34, 0)
		bend_camera.look_at(Vector3(point.x, 0, point.y))
		bend_camera.far = 4000.0
		await _capture(bend_camera, "res://tests/sydney_road_bend.png", "road bend %.2f rad on %s" % [bend["angle"], bend["road"]])

	var junction := _find_junction(data.get("junctions", []), spawn)
	if not junction.is_empty():
		var center := Vector3(float(junction["x"]), 0.0, float(junction["z"]))
		var junction_camera := Camera3D.new()
		world.add_child(junction_camera)
		junction_camera.global_position = center + Vector3(28, 34, 28)
		junction_camera.look_at(center)
		junction_camera.far = 4000.0
		await _capture(junction_camera, "res://tests/sydney_junction.png", "junction %s" % junction.get("id", ""))

	var concave := _find_concave_building(data.get("buildings", []))
	if not concave.is_empty():
		# Dense CBD neighbours obscure an exterior close-up. Hide the aggregate
		# building mesh and show only this footprint for the diagnostic shot.
		var all_buildings: Node = world.sydney_world.get_node_or_null("Buildings")
		if all_buildings != null:
			all_buildings.visible = false
		var isolated := SydneyMesh.buildings([concave])
		var showcase := MeshInstance3D.new()
		showcase.name = "ConcaveShowcase"
		showcase.mesh = isolated.get("mesh")
		world.add_child(showcase)
		var ring: Array = concave["ring"]
		var centroid := Vector2.ZERO
		for point in ring:
			centroid += Vector2(float(point[0]), float(point[1]))
		centroid /= float(ring.size())
		var height := float(concave.get("heightM", 10.0))
		var radius := maxf(22.0, sqrt(float(concave.get("areaM2", 400.0))) * 1.5)
		var building_camera := Camera3D.new()
		world.add_child(building_camera)
		building_camera.global_position = Vector3(centroid.x + radius, maxf(height + 22.0, 32.0), centroid.y + radius)
		building_camera.look_at(Vector3(centroid.x, 0.0, centroid.y))
		building_camera.far = 4000.0
		await _capture(building_camera, "res://tests/sydney_concave_building.png", "concave building %s" % concave.get("id", ""))

	world.queue_free()
	await process_frame
	quit()
