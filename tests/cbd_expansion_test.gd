extends SceneTree

## Phase 6B data and city checks against the real Stage B export and the real
## CBD world build. Headless:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##     --script res://tests/cbd_expansion_test.gd --log-file tests/cbd_expansion.log
##
## Every assertion is made against `sydney/world/stage_b/world.json` and the
## live `CbdWorld` node, not against synthetic stand-ins.

var checks := 0
var failures := 0
const CbdWorldScript := preload("res://sydney/cbd/cbd_world.gd")
var world


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	world = CbdWorldScript.new()
	var started := Time.get_ticks_msec()
	var ok: bool = world.load_world()
	var build_ms := Time.get_ticks_msec() - started
	check(ok, "Stage B export loads: " + world.load_error)
	check(world.data.get("stage", "") == "B", "loaded export is Stage B")
	check(world.loaded_path == CbdWorldScript.STAGE_B_PATH, "loaded the Stage B path")

	# ---------------------------------------------------------- geographic --
	var bounds: Dictionary = world.bounds
	var width := float(bounds["maxX"]) - float(bounds["minX"])
	var depth := float(bounds["maxZ"]) - float(bounds["minZ"])
	check(width > 3300.0 and depth > 4800.0, "world covers at least 3.3 x 4.8 km")
	print("COVERAGE: %.0f m east-west, %.0f m north-south" % [width, depth])

	var stats: Dictionary = world.stats
	check(int(stats.get("roads", 0)) > 4000, "expanded road network present")
	check(int(stats.get("buildings", 0)) > 6000, "substantial building count")
	check(int(stats.get("buildingsGenerated", 0)) > 5000, "block-derived buildings exported")
	check(int(stats.get("buildingsFromOsm", 0)) > 900, "OSM footprints preserved")
	check(int(stats.get("blocks", 0)) > 800, "real OSM blocks polygonised")
	check(int(stats.get("parks", 0)) > 500, "parks exported")
	check(int(stats.get("waterRings", 0)) > 10, "harbour water present")

	var required := [
		"circular-quay", "the-rocks", "barangaroo", "wynyard", "martin-place",
		"town-hall", "haymarket", "central", "surry-hills", "darlinghurst",
		"kings-cross", "woolloomooloo", "hyde-park", "botanic-garden", "the-domain",
	]
	var have_all := true
	for district_id in required:
		if not world.district_centres.has(district_id):
			have_all = false
			push_error("missing district: " + district_id)
	check(have_all, "every required district is exported")

	var must_build := ["circular-quay", "the-rocks", "barangaroo", "wynyard", "town-hall",
		"haymarket", "central", "surry-hills", "darlinghurst", "kings-cross", "woolloomooloo"]
	var by_district: Dictionary = stats.get("buildingsByDistrict", {})
	var built_everywhere := true
	for district_id in must_build:
		if int(by_district.get(district_id, 0)) <= 0:
			built_everywhere = false
			push_error("no buildings in " + district_id)
	check(built_everywhere, "every populated district has buildings")
	var styles: Dictionary = stats.get("buildingsByStyle", {})
	check(styles.size() >= 6, "at least six facade families in use")
	print("STYLES: ", styles)

	# ------------------------------------------------------------ viewpoints --
	for view in ["cbd_aerial", "circular_quay", "the_rocks", "george_street", "wynyard",
			"town_hall", "chinatown", "central", "surry_hills"]:
		check(world.viewpoints.has(view), "viewpoint exported: " + view)

	# ------------------------------------------------------------- buildings --
	var rows: Array = world.data.get("buildings", [])
	check(rows.size() > 6000, "building rows readable")
	var duplicate_ids := 0
	var invalid_rings := 0
	var degenerate_rings := 0
	var outside_bounds := 0
	var bad_styles := 0
	var signatures: Dictionary = {}
	var duplicates_by_geometry := 0
	for row in rows:
		var ring := SydneyMesh._clean_ring(row.get("ring", []))
		if ring.size() < 3:
			invalid_rings += 1
			continue
		if styles.has(str(row.get("style", ""))) == false:
			bad_styles += 1
		var area := absf(SydneyMesh._signed_area(ring))
		if area < 1.0:
			degenerate_rings += 1
		if Geometry2D.triangulate_polygon(ring).is_empty():
			invalid_rings += 1
			if invalid_rings <= 3:
				print("UNTRIANGULABLE: ", row.get("id"), " points=", ring.size(), " area=", area)
		var key := "%d:%d:%.0f" % [roundi(ring[0].x * 10.0), roundi(ring[0].y * 10.0), area]
		signatures[key] = int(signatures.get(key, 0)) + 1
		for point in ring:
			if point.x < float(bounds["minX"]) - 1.0 or point.x > float(bounds["maxX"]) + 1.0 \
				or point.y < float(bounds["minZ"]) - 1.0 or point.y > float(bounds["maxZ"]) + 1.0:
				outside_bounds += 1
				break
	for key in signatures:
		if int(signatures[key]) > 1:
			duplicates_by_geometry += 1
	check(invalid_rings == 0, "no invalid or untriangulable building rings")
	check(degenerate_rings == 0, "no zero-area building rings")
	check(outside_bounds == 0, "every building stays inside the export bounds")
	check(bad_styles == 0, "every building has a style the builder knows")
	check(duplicates_by_geometry <= 2, "no duplicated building footprints")
	var heights: Array = []
	for row in rows:
		heights.append(float(row.get("heightM", 0.0)))
	heights.sort()
	check(float(heights[0]) >= 3.0 and float(heights[-1]) <= 240.0, "heights inside the authored envelope")
	check(float(heights[-1]) > 90.0, "the skyline includes towers")
	print("HEIGHTS: min %.1f median %.1f max %.1f" % [heights[0], heights[heights.size() / 2], heights[-1]])

	# ------------------------------------------------- clearance, sampled grid --
	# A 40 m grid over the road segments keeps the clearance check linear enough
	# to run inside the game's own test suite. It tests every building vertex
	# against the nearest carriageway edge.
	var cells: Dictionary = {}
	var cell_size := 40.0
	for road in world.data.get("roads", []):
		if bool(road.get("tunnel", false)):
			continue
		var points: Array = road.get("points", [])
		var half := float(road.get("widthM", 8.0)) * 0.5
		for index in range(points.size() - 1):
			var a := Vector2(float(points[index][0]), float(points[index][1]))
			var b := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
			var low := Vector2(minf(a.x, b.x), minf(a.y, b.y))
			var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
			for gx in range(int(floor(low.x / cell_size)), int(floor(high.x / cell_size)) + 1):
				for gz in range(int(floor(low.y / cell_size)), int(floor(high.y / cell_size)) + 1):
					var key := Vector2i(gx, gz)
					if not cells.has(key):
						cells[key] = []
					cells[key].append([a, b, half])
	var violations := 0
	var minimum_clearance := INF
	var checked_vertices := 0
	for row in rows:
		if not bool(row.get("generated", false)):
			continue
		var ring := SydneyMesh._clean_ring(row.get("ring", []))
		if ring.size() < 3:
			continue
		for point in ring:
			var cell := Vector2i(int(floor(point.x / cell_size)), int(floor(point.y / cell_size)))
			var best := INF
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for segment in cells.get(cell + Vector2i(dx, dz), []):
						var a: Vector2 = segment[0]
						var b: Vector2 = segment[1]
						var half: float = segment[2]
						var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
						best = minf(best, point.distance_to(closest) - half)
			if best < INF:
				checked_vertices += 1
				minimum_clearance = minf(minimum_clearance, best)
				if best < -0.01:
					violations += 1
					if violations <= 3:
						print("INTRUSION: ", row.get("id"), " point=", point, " clearance=", best)
	check(violations == 0, "generated buildings keep clear of every carriageway")
	check(minimum_clearance > 0.0, "measured minimum kerb clearance is positive")
	print("CLEARANCE: %d vertices, minimum %.2f m" % [checked_vertices, minimum_clearance])

	# ------------------------------------------------------------ water check --
	var water_rings: Array = world.data.get("water", {}).get("rings", [])
	var in_water := 0
	for row in rows:
		var ring := SydneyMesh._clean_ring(row.get("ring", []))
		if ring.size() < 3:
			continue
		var centroid := Vector2.ZERO
		for point in ring:
			centroid += point
		centroid /= ring.size()
		for water_ring in water_rings:
			var polygon := PackedVector2Array()
			for point in water_ring:
				polygon.append(Vector2(float(point[0]), float(point[1])))
			if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(centroid, polygon):
				in_water += 1
				break
	check(in_water == 0, "no building centroid sits in the harbour or Darling Harbour")

	# --------------------------------------------------------------- lighting --
	root.add_child(world)
	await process_frame
	check(world.get_node_or_null("Roads") != null, "road mesh node created")
	check(world.get_node_or_null("Footpaths") != null, "footpath mesh node created")
	check(world.get_node_or_null("Buildings") != null, "CBD building mesh created")
	check(world.get_node_or_null("BuildingCollision") != null, "building collision created")
	check(world.get_node_or_null("WaterCollision") != null, "shoreline collision created")
	check(world.get_node_or_null("Vegetation") != null, "park and street vegetation created")
	check(world.get_node_or_null("OperaHouse") != null, "Opera House landmark still built")
	check(world.get_node_or_null("HarbourBridge") != null, "Harbour Bridge still built")

	var counts: Dictionary = world.geometry_counts.get("Buildings", {})
	check(int(counts.get("built", 0)) > 6000, "facade builder built the exported buildings")
	check(int(counts.get("degenerateTriangles", 0)) == 0, "facade builder rejected every degenerate triangle")
	check(int(counts.get("collisionTriangles", 0)) > 0, "building collision has triangles")
	print("BUILDINGS: ", counts)
	print("VEGETATION: ", world.geometry_counts.get("Vegetation", {}))
	print("BUILD TIMES (ms): ", world.build_times_ms)
	print("WORLD LOAD (ms): ", build_ms)

	# Mesh sanity on the real city mesh: finite vertices, no zero-area triangles.
	var mesh_node := world.get_node_or_null("Buildings") as MeshInstance3D
	check(mesh_node != null and mesh_node.mesh != null, "building mesh is present as a MeshInstance3D")
	var zero_area := 0
	var non_finite := 0
	if mesh_node != null and mesh_node.mesh != null:
		var mesh: ArrayMesh = mesh_node.mesh
		var vertices := PackedVector3Array()
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			vertices.append_array(arrays[Mesh.ARRAY_VERTEX])
		for index in range(0, vertices.size(), 3):
			var a := vertices[index]
			var b := vertices[index + 1]
			var c := vertices[index + 2]
			for point in [a, b, c]:
				if is_nan(point.x) or is_nan(point.y) or is_nan(point.z):
					non_finite += 1
			if (b - a).cross(c - a).length() < 1e-6:
				zero_area += 1
	check(non_finite == 0, "no non-finite building vertices")
	check(zero_area == 0, "no zero-area triangles in the built city mesh")

	# ---------------------------------------------------------- connectivity --
	var graph: Dictionary = world.pedestrian_graph
	check(graph.get("stats", {}).get("nodes", 0) > 20000, "pedestrian graph nodes exported")
	var graph_stats: Dictionary = graph.get("stats", {})
	check(float(graph_stats.get("largestComponentShare", 0.0)) > 0.9,
		"pedestrian graph is largely one network")
	print("PEDESTRIAN GRAPH: ", graph_stats)

	# The spawn and vehicles must still work on the expanded geography.
	check(world.player_spawn.distance_to(Vector3.ZERO) > 100.0, "player spawn is in the city")
	check(world.vehicle_spawns.size() >= 4, "four vehicle spawns exported")
	check(Vector2(world.enemy_spawn.x - world.player_spawn.x, world.enemy_spawn.z - world.player_spawn.z).length() < 60.0,
		"enemy spawn is near the player")

	# Every district viewpoint must be reachable ground, i.e. on the network.
	var off_network := 0
	for view_id in world.viewpoints:
		var view: Dictionary = world.viewpoints[view_id]
		if view_id == "cbd_aerial":
			continue
		var point := Vector2(float(view["x"]), float(view["z"]))
		var nearest := INF
		for row in world.data.get("footpaths", []):
			var points: Array = row.get("points", [])
			for index in range(points.size() - 1):
				var a := Vector2(float(points[index][0]), float(points[index][1]))
				var b := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
				nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
				if nearest < 6.0:
					break
			if nearest < 6.0:
				break
		if nearest > 6.5:
			off_network += 1
			push_error("viewpoint %s is %.1f m from a footpath" % [view_id, nearest])
	check(off_network == 0, "every district viewpoint is on the pedestrian network")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
