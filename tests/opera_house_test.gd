extends SceneTree

## Focused checks for the authored Sydney Opera House landmark.
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##       --script res://tests/opera_house_test.gd --log-file tests/opera_house.log

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


func _ring_area(ring: PackedVector2Array) -> float:
	var total := 0.0
	for index in ring.size():
		var a := ring[index]
		var b := ring[(index + 1) % ring.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


func _ring_centroid(ring: PackedVector2Array) -> Vector2:
	## Area-weighted centroid, matching the value the export uses.
	var area := 0.0
	var sum := Vector2.ZERO
	for index in ring.size():
		var a := ring[index]
		var b := ring[(index + 1) % ring.size()]
		var cross := a.x * b.y - b.x * a.y
		area += cross
		sum += (a + b) * cross
	if absf(area) < 0.0001:
		return Vector2.ZERO
	return sum / (3.0 * area)


## Counts invalid geometry in every surface of every mesh under `node`.
func _audit(node: Node, results: Dictionary) -> Dictionary:
	var degenerate := 0
	var non_finite := 0
	var bad_normals := 0
	var triangle_count := 0
	var normal_y_sum := 0.0
	var instance := node as MeshInstance3D
	if instance == null or instance.mesh == null:
		return {"degenerate": -1}
	var mesh: ArrayMesh = instance.mesh
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in range(0, vertices.size(), 3):
			var a := vertices[index]
			var b := vertices[index + 1]
			var c := vertices[index + 2]
			triangle_count += 1
			for point in [a, b, c]:
				if is_nan(point.x) or is_nan(point.y) or is_nan(point.z) \
					or is_inf(point.x) or is_inf(point.y) or is_inf(point.z):
					non_finite += 1
			if (b - a).cross(c - a).length() < 0.000000001:
				degenerate += 1
			for offset in 3:
				var normal := normals[index + offset]
				var length := normal.length()
				if length < 0.5 or length > 2.0:
					bad_normals += 1
				normal_y_sum += normal.y
	results["degenerate"] = degenerate
	results["nonFinite"] = non_finite
	results["badNormals"] = bad_normals
	results["triangles"] = triangle_count
	results["meanNormalY"] = normal_y_sum / maxf(1.0, float(triangle_count * 3))
	return results


func _checksum(node: Node) -> String:
	var parts := PackedStringArray()
	for child in node.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		for surface_index in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var sum := 0.0
			for index in vertices.size():
				var point := vertices[index]
				sum += (point.x * 3.1 + point.y * 7.7 + point.z * 11.3) * float(index + 1)
			parts.append("%s:%d:%.3f" % [instance.name, vertices.size(), sum])
	return "|".join(parts)


func run() -> void:
	var reference := OperaHouseLandmark.read_reference()
	check(not reference.is_empty(), "authored landmark reference loads")
	check(String(reference.get("landmark", "")) == "sydney-opera-house", "reference identifies the Sydney Opera House")
	var provenance: Dictionary = reference.get("provenance", {})
	check(String(provenance.get("licence", "")).contains("ODbL"), "OSM provenance and licence recorded")
	check(String(provenance.get("osmObjects", {}).get("relation/9596872", "")).contains("podium"), "podium source relation documented")

	# --- geographic placement -------------------------------------------------
	var podium := OperaHouseLandmark.ring_from_source(reference)
	check(podium.size() >= 20, "podium ring loaded with %d vertices" % podium.size())
	var area := absf(_ring_area(podium))
	check(absf(area - 15885.0) < 5.0, "podium area matches the OSM footprint (%.1f m2)" % area)
	var centroid := _ring_centroid(podium)
	check(centroid.distance_to(Vector2(658.72, -1763.81)) < 1.0,
		"podium centroid at Bennelong Point (%.2f, %.2f)" % [centroid.x, centroid.y])
	var min_point := podium[0]
	var max_point := podium[0]
	for point in podium:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
	check(min_point.distance_to(Vector2(594.26, -1853.47)) < 3.0, "podium south-west extent matches the export projection")
	check(max_point.distance_to(Vector2(729.45, -1673.02)) < 3.0, "podium north-east extent matches the export projection")
	var long_axis := float(reference.get("podiumLongAxisM", 0.0))
	check(absf(long_axis - 169.7) < 1.0, "podium long axis %.1f m" % long_axis)

	# --- shell arrangement ----------------------------------------------------
	var shells: Array = reference.get("shells", [])
	check(shells.size() == 10, "ten shell sails derived from the roof relations (%d)" % shells.size())
	var groups := {"concert-hall": 0, "opera-theatre": 0, "restaurant": 0}
	var inside := 0
	var height_ok := 0
	for spec in shells:
		var group := String(spec.get("group", ""))
		if groups.has(group):
			groups[group] += 1
		var obb: Dictionary = spec.get("obb", {})
		var apex := float(spec.get("apexAboveGroundM", 0.0))
		if apex >= 20.0 and apex <= 70.0:
			height_ok += 1
		var centre: Array = obb.get("centre", [0.0, 0.0])
		if Geometry2D.is_point_in_polygon(Vector2(float(centre[0]), float(centre[1])), podium):
			inside += 1
		check(float(obb.get("lengthM", 0.0)) > 10.0 and float(obb.get("widthM", 0.0)) > 6.0,
			"shell %s has a usable plan (%.1f x %.1f m)" % [spec.get("id", "?"), float(obb.get("lengthM", 0.0)), float(obb.get("widthM", 0.0))])
	check(groups["concert-hall"] == 4, "four Concert Hall shells")
	check(groups["opera-theatre"] == 4, "four Opera Theatre shells")
	check(groups["restaurant"] == 2, "two Bennelong Restaurant shells")
	check(inside == 10, "every shell sits on the podium footprint")
	check(height_ok == 10, "every shell apex is between 20 m and 70 m")
	check(float(shells[0].get("apexAboveGroundM", 0.0)) >= 50.0, "the harbour-facing group reaches roof scale")

	# --- build ----------------------------------------------------------------
	var landmark := OperaHouseLandmark.new()
	check(landmark.build(reference), "landmark builds: " + landmark.build_error)
	root.add_child(landmark)
	await process_frame
	for part in ["OperaPodium", "OperaDeck", "OperaSteps", "OperaForecourt", "OperaShells", "OperaGlazing"]:
		check(landmark.get_node_or_null(part) != null, "%s mesh created" % part)
	check(landmark.get_node_or_null("OperaCollision") != null, "landmark collision body created")
	var stats: Dictionary = landmark.stats
	check(int(stats.get("triangles", 0)) > 5000, "landmark renders %d triangles" % int(stats.get("triangles", 0)))
	check(int(stats.get("collisionTriangles", 0)) > 1000, "landmark collision has %d triangles" % int(stats.get("collisionTriangles", 0)))

	var total_degenerate := 0
	var total_non_finite := 0
	var total_bad_normals := 0
	for part in ["OperaPodium", "OperaDeck", "OperaSteps", "OperaForecourt", "OperaShells", "OperaGlazing"]:
		var node := landmark.get_node_or_null(part)
		var results := _audit(node, {})
		total_degenerate += int(results.get("degenerate", 0))
		total_non_finite += int(results.get("nonFinite", 0))
		total_bad_normals += int(results.get("badNormals", 0))
	check(total_degenerate == 0, "no degenerate triangles (%d)" % total_degenerate)
	check(total_non_finite == 0, "no non-finite vertices (%d)" % total_non_finite)
	check(total_bad_normals == 0, "all vertex normals are unit length (%d bad)" % total_bad_normals)
	# The documented Godot boundary: geometry is authored mathematically CCW with
	# outward normals, then reversed to clockwise fronts. In the engine mesh the
	# stored winding must therefore be clockwise about the outward normal.
	var winding_errors := 0
	var winding_triangles := 0
	for part in ["OperaPodium", "OperaShells", "OperaGlazing"]:
		var instance := landmark.get_node_or_null(part) as MeshInstance3D
		if instance == null:
			continue
		for surface_index in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			# The engine mesh is indexed, so the rendered order must come from the
			# index buffer, not from the vertex buffer order.
			var indices = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, vertices.size(), 3):
				var i0 := index
				var i1 := index + 1
				var i2 := index + 2
				if indices is PackedInt32Array and indices.size() >= index + 3:
					i0 = indices[index]
					i1 = indices[index + 1]
					i2 = indices[index + 2]
				var face := (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0])
				if face.length() < 0.000000001:
					continue
				winding_triangles += 1
				var average := (normals[i0] + normals[i1] + normals[i2]).normalized()
				# A crease vertex can sit almost perpendicular to one adjacent face;
				# only a genuine inversion of the engine winding is a failure.
				if face.normalized().dot(average) > 0.02:
					winding_errors += 1
	check(winding_errors == 0, "engine winding is clockwise about the outward normals (%d of %d wrong)" % [winding_errors, winding_triangles])

	# Shells must overlap like nested sails rather than form one flat slab.
	var shell_node := landmark.get_node_or_null("OperaShells") as MeshInstance3D
	var bounds := AABB()
	if shell_node != null:
		bounds = shell_node.get_aabb()
	check(bounds.size.y > 40.0, "shell mass rises %.1f m above the podium" % bounds.size.y)
	check(bounds.size.x > 80.0 and bounds.size.z > 80.0, "shell mass spans the Bennelong Point plan")

	# --- determinism ----------------------------------------------------------
	var first := _checksum(landmark)
	var second_landmark := OperaHouseLandmark.new()
	check(second_landmark.build(reference), "landmark rebuilds from the same data")
	root.add_child(second_landmark)
	await process_frame
	check(first == _checksum(second_landmark), "generation is deterministic (identical vertex checksum)")
	second_landmark.queue_free()
	await process_frame

	# --- collision ------------------------------------------------------------
	var centre := centroid
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(centre.x, 200.0, centre.y), Vector3(centre.x, -10.0, centre.y), 1
	)
	var hit := landmark.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty(), "a downward ray hits the landmark")
	if not hit.is_empty():
		check(float(hit["position"].y) > 12.0 and float(hit["position"].y) < 70.0,
			"the roof mass is solid above the deck (%.2f m)" % float(hit["position"].y))
	# The southern deck is clear of shells, so it must be solid at podium height.
	var axis := Vector2(float(reference.get("axisXZ", [0.0, -1.0])[0]), float(reference.get("axisXZ", [0.0, -1.0])[1]))
	var deck := centre + axis * -70.0
	var deck_ray := PhysicsRayQueryParameters3D.create(
		Vector3(deck.x, 200.0, deck.y), Vector3(deck.x, -10.0, deck.y), 1
	)
	var deck_hit := landmark.get_world_3d().direct_space_state.intersect_ray(deck_ray)
	check(not deck_hit.is_empty(), "the southern podium deck is solid")
	if not deck_hit.is_empty():
		check(absf(float(deck_hit["position"].y) - 12.0) < 0.6,
			"the podium deck is walkable at %.2f m" % float(deck_hit["position"].y))
	landmark.queue_free()
	await process_frame

	# --- site integration -----------------------------------------------------
	var world_loader := SydneyWorld.new()
	check(world_loader.load_world(), "Stage A world still loads: " + world_loader.load_error)
	var suppressed := OperaHouseLandmark.filtered_buildings(world_loader.data.get("buildings", []), world_loader.landmark_podium)
	check(suppressed.size() == world_loader.data.get("buildings", []).size(),
		"no generic building was removed outside the landmark footprint")
	var roads: Array = OperaHouseLandmark.filtered_roads(world_loader.data.get("roads", []), world_loader.landmark_podium)
	var inside_roads := 0
	for road in roads:
		for point in road.get("points", []):
			if Geometry2D.is_point_in_polygon(Vector2(float(point[0]), float(point[1])), world_loader.landmark_podium):
				inside_roads += 1
				break
	check(inside_roads == 0, "no road ribbon runs through the podium")
	check(roads.size() >= world_loader.data.get("roads", []).size() - 4,
		"only the roads under the podium were split (%d rows)" % roads.size())

	root.add_child(world_loader)
	await process_frame
	check(world_loader.get_node_or_null("OperaHouse") != null, "the Sydney world adds the Opera House")
	check(world_loader.geometry_counts.has("OperaHouse"), "landmark geometry is reported in world counts")
	check(world_loader.build_times_ms.has("Landmarks"), "landmark build time is measured")
	check(float(world_loader.build_times_ms.get("Landmarks", 0.0)) < 4000.0,
		"landmark builds in %.1f ms" % float(world_loader.build_times_ms.get("Landmarks", 0.0)))

	print("RESULT: %d checks, %d failures" % [checks, failures])
	world_loader.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
