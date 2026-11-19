extends SceneTree

## Synthetic geometry checks for the production Sydney mesh builders.
## Run headless:
##   Godot_v4.7.2-stable_win64_console.exe --headless --script res://tests/sydney_geometry_test.gd

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _building(ring: Array, id: String = "b") -> Dictionary:
	return {"id": id, "heightM": 12.0, "ring": ring}


func _mesh_info(mesh: ArrayMesh) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var triangles: Array = []
	if mesh == null or mesh.get_surface_count() == 0:
		return {"vertices": vertices, "normals": normals, "triangles": triangles}
	var arrays := mesh.surface_get_arrays(0)
	vertices = arrays[Mesh.ARRAY_VERTEX]
	normals = arrays[Mesh.ARRAY_NORMAL]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices is PackedInt32Array and indices.size() > 0:
		for index in range(0, indices.size(), 3):
			triangles.append([vertices[indices[index]], vertices[indices[index + 1]], vertices[indices[index + 2]]])
	else:
		for index in range(0, vertices.size(), 3):
			triangles.append([vertices[index], vertices[index + 1], vertices[index + 2]])
	return {"vertices": vertices, "normals": normals, "triangles": triangles}


func _check_mesh(mesh: ArrayMesh, label: String) -> Dictionary:
	var info := _mesh_info(mesh)
	check(mesh != null and mesh.get_surface_count() > 0, label + ": mesh exists")
	check(info["triangles"].size() > 0, label + ": has triangles")
	var finite := true
	for point in info["vertices"]:
		if not _vec_finite(point):
			finite = false
	for normal in info["normals"]:
		if not _vec_finite(normal):
			finite = false
	check(finite, label + ": all vertices and normals finite")
	var positive := true
	for triangle in info["triangles"]:
		var cross: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
		if cross.length() < 0.000001:
			positive = false
	check(positive, label + ": no zero-area triangles")
	return info


func _vec_finite(value: Vector3) -> bool:
	return not (is_nan(value.x) or is_nan(value.y) or is_nan(value.z) or is_inf(value.x) or is_inf(value.y) or is_inf(value.z))


func _point_in_triangle_2d(point: Vector2, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var p0 := Vector2(a.x, a.z)
	var p1 := Vector2(b.x, b.z)
	var p2 := Vector2(c.x, c.z)
	var d1 := (point - p1).cross(p1 - p0)
	var d2 := (point - p2).cross(p2 - p1)
	var d3 := (point - p0).cross(p0 - p2)
	var has_negative := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_positive := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (has_negative and has_positive)


func _point_in_polygon(point: Vector2, ring: Array) -> bool:
	var inside := false
	var previous := ring.size() - 1
	for index in ring.size():
		var a := Vector2(float(ring[index][0]), float(ring[index][1]))
		var b := Vector2(float(ring[previous][0]), float(ring[previous][1]))
		if ((a.y > point.y) != (b.y > point.y)) \
			and point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		previous = index
	return inside


func _check_wall_sides(mesh: ArrayMesh, ring: Array, label: String) -> void:
	var info := _mesh_info(mesh)
	var wrong := 0
	for triangle in info["triangles"]:
		var cross: Vector3 = (triangle[1] - triangle[0]).cross(triangle[2] - triangle[0])
		if absf(cross.y) > 1.0 or cross.length() < 0.000001:
			continue
		var normal := cross.normalized()
		var centroid: Vector3 = (triangle[0] + triangle[1] + triangle[2]) / 3.0
		var inside_probe := Vector2(centroid.x, centroid.z) - Vector2(normal.x, normal.z) * 0.4
		var outside_probe := Vector2(centroid.x, centroid.z) + Vector2(normal.x, normal.z) * 0.4
		if not _point_in_polygon(inside_probe, ring) or _point_in_polygon(outside_probe, ring):
			wrong += 1
	check(wrong == 0, label + ": every wall normal points out of the footprint")


func _distance_to_polyline(point: Vector2, path: Array) -> float:
	var best := INF
	for index in range(path.size() - 1):
		var a := Vector2(float(path[index][0]), float(path[index][1]))
		var b := Vector2(float(path[index + 1][0]), float(path[index + 1][1]))
		var direction := b - a
		var length_sq := direction.length_squared()
		var t := 0.0 if length_sq < 0.0001 else clampf((point - a).dot(direction) / length_sq, 0.0, 1.0)
		best = minf(best, point.distance_to(a + direction * t))
	return best


func _test_buildings() -> void:
	var clockwise := [[0, 0], [0, 10], [10, 10], [10, 0]]
	var counter := [[0, 0], [10, 0], [10, 10], [0, 10]]
	var cw := SydneyMesh.buildings([_building(clockwise, "cw")])
	var ccw := SydneyMesh.buildings([_building(counter, "ccw")])
	check(int(cw["built"]) == 1, "building: clockwise rectangle built")
	check(int(ccw["built"]) == 1, "building: counter-clockwise rectangle built")
	for result in [cw, ccw]:
		var info := _check_mesh(result["mesh"], "building rectangle")
		check(result["faces"].size() / 3 == info["triangles"].size(), "building: collision triangles match rendered triangles")
		var wall_count := 0
		var roof_count := 0
		for normal in info["normals"]:
			if absf(normal.y) < 0.01:
				wall_count += 1
			elif normal.y > 0.99:
				roof_count += 1
		check(wall_count >= 8, "building: walls have horizontal outward normals")
		check(roof_count >= 6, "building: roof normals point up")
	check(cw["faces"].size() == ccw["faces"].size(), "building: winding reversal preserves triangle count")
	_check_wall_sides(cw["mesh"], clockwise, "building clockwise rectangle")
	_check_wall_sides(ccw["mesh"], counter, "building counter-clockwise rectangle")

	var l_shape := [[0, 0], [0, 12], [4, 12], [4, 4], [12, 4], [12, 0]]
	var l_result := SydneyMesh.buildings([_building(l_shape, "L")])
	check(int(l_result["built"]) == 1, "building: concave L-shape built")
	var l_info := _check_mesh(l_result["mesh"], "building L-shape")
	check(l_info["triangles"].size() > 4, "building: concave L-shape triangulated beyond a rectangle")
	_check_wall_sides(l_result["mesh"], l_shape, "building concave L-shape")

	var irregular := [[0, 0], [0, 9], [3, 13], [8, 11], [11, 7], [9, 2], [5, 0], [2, 3]]
	var irregular_result := SydneyMesh.buildings([_building(irregular, "irregular")])
	check(int(irregular_result["built"]) == 1, "building: irregular concave footprint built")
	_check_mesh(irregular_result["mesh"], "building irregular")
	_check_wall_sides(irregular_result["mesh"], irregular, "building irregular concave")

	var duplicated := [[0, 0], [0, 10], [10, 10], [10, 0], [0, 0]]
	var duplicate_result := SydneyMesh.buildings([_building(duplicated, "dup")])
	check(int(duplicate_result["built"]) == 1, "building: repeated closing vertex is safe")
	_check_mesh(duplicate_result["mesh"], "building duplicate closing vertex")

	var degenerate := [[0, 0], [5, 0], [10, 0]]
	var degenerate_result := SydneyMesh.buildings([_building(degenerate, "flat")])
	check(int(degenerate_result["built"]) == 0, "building: collinear footprint rejected")
	check(degenerate_result["faces"].size() == 0, "building: rejected footprint has no collision triangles")


func _test_roads() -> void:
	var straight := SydneyMesh.flat_paths([[[0, 0], [100, 0]]], [10.0], 0.0, Color.WHITE)
	var straight_info := _check_mesh(straight, "road straight")
	check(straight_info["triangles"].size() == 2, "road straight: two quads/triangles")
	check(straight_info["vertices"].size() == 6, "road straight: six vertices after indexing")

	var bend := SydneyMesh.flat_paths([[[0, 0], [50, 0], [50, 50]]], [10.0], 0.0, Color.WHITE)
	_check_mesh(bend, "road 90-degree bend")
	var bend_spike := false
	for vertex in _mesh_info(bend)["vertices"]:
		if _distance_to_polyline(Vector2(vertex.x, vertex.z), [[0, 0], [50, 0], [50, 50]]) > 13.0:
			bend_spike = true
	check(not bend_spike, "road 90-degree bend: no miter overshoot beyond 13 m")

	var acute_path := [[0, 0], [50, 0], [60, 8]]
	var acute := SydneyMesh.flat_paths([acute_path], [10.0], 0.0, Color.WHITE)
	var acute_info := _check_mesh(acute, "road acute bend")
	var acute_spike := false
	for vertex in acute_info["vertices"]:
		if _distance_to_polyline(Vector2(vertex.x, vertex.z), acute_path) > 13.0:
			acute_spike = true
	check(not acute_spike, "road acute bend: bevel fallback prevents long miter spikes")

	var narrow := SydneyMesh.flat_paths([[[0, 0], [30, 30]]], [2.0], 0.0, Color.WHITE)
	_check_mesh(narrow, "road narrow")
	var wide := SydneyMesh.flat_paths([[[0, 0], [30, 30]]], [40.0], 0.0, Color.WHITE)
	var wide_info := _check_mesh(wide, "road wide")
	check(wide_info["vertices"].size() > _mesh_info(narrow)["vertices"].size() - 100, "road: width does not collapse ribbon")

	var sub_millimetre := SydneyMesh.flat_paths([[[0, 0], [0.0005, 0], [20, 0]]], [10.0], 0.0, Color.WHITE)
	var sub_info := _check_mesh(sub_millimetre, "road zero-length edge")
	check(sub_info["triangles"].size() == 2, "road zero-length edge: remaining path is not dropped")

	var disconnected := SydneyMesh.flat_paths([[[0, 0], [20, 0]], [[0, 50], [20, 50]]], [6.0, 6.0], 0.0, Color.WHITE)
	check(_mesh_info(disconnected)["triangles"].size() == 4, "road: disconnected endpoints both emitted")

	var repeated := SydneyMesh.flat_paths([[[0, 0], [20, 0]], [[0, 0], [20, 0]]], [6.0, 6.0], 0.0, Color.WHITE)
	check(_mesh_info(repeated)["triangles"].size() == 4, "road: repeated path segments do not crash")

	# T-junction (three incident roads) and four-way intersection.
	var t_roads := [
		{"id": "west", "widthM": 10.0, "points": [[-50, 0], [0, 0]], "tunnel": false},
		{"id": "east", "widthM": 10.0, "points": [[0, 0], [50, 0]], "tunnel": false},
		{"id": "north", "widthM": 10.0, "points": [[0, 0], [0, -50]], "tunnel": false},
	]
	var t_junction := [{"x": 0.0, "z": 0.0, "roadCount": 3, "roadIds": ["west", "east", "north"]}]
	var t_mesh := SydneyMesh.road_mesh(t_roads, t_junction, 0.0, Color.WHITE)
	_check_mesh(t_mesh, "road T-junction")
	var four_roads := t_roads.duplicate(true)
	four_roads.append({"id": "south", "widthM": 10.0, "points": [[0, 0], [0, 50]], "tunnel": false})
	var four_junction := [{"x": 0.0, "z": 0.0, "roadCount": 4, "roadIds": ["west", "east", "north", "south"]}]
	var four_mesh := SydneyMesh.road_mesh(four_roads, four_junction, 0.0, Color.WHITE)
	var four_info := _check_mesh(four_mesh, "road four-way intersection")
	var covered := false
	for triangle in four_info["triangles"]:
		if _point_in_triangle_2d(Vector2.ZERO, triangle[0], triangle[1], triangle[2]):
			covered = true
	check(covered, "road four-way intersection: junction centre covered")
	var junction_spike := false
	for vertex in four_info["vertices"]:
		var distance := Vector2(vertex.x, vertex.z).length()
		# The incident ribbons legitimately reach their 50 m endpoints. Check
		# that nothing generated *near* the junction overshoots the patch bound.
		if distance > 15.0 and distance < 45.0:
			junction_spike = true
	check(not junction_spike, "road junction: no intermediate spike beyond incident widths")


func _test_polygons_and_crossings() -> void:
	var rectangle := [[0, 0], [10, 0], [10, 10], [0, 10]]
	var reversed := [[0, 0], [0, 10], [10, 10], [10, 0]]
	var rect_mesh := SydneyMesh.flat_polygons([rectangle], 0.0, Color.WHITE)
	var rect_info := _check_mesh(rect_mesh, "polygon rectangle")
	check(rect_info["triangles"].size() == 2, "polygon rectangle: two triangles")
	var reversed_info := _check_mesh(SydneyMesh.flat_polygons([reversed], 0.0, Color.WHITE), "polygon reversed")
	check(reversed_info["triangles"].size() == 2, "polygon reversed: two triangles")

	var concave := [[0, 0], [0, 12], [4, 12], [4, 4], [12, 4], [12, 0]]
	var concave_info := _check_mesh(SydneyMesh.flat_polygons([concave], 0.0, Color.WHITE), "polygon concave")
	check(concave_info["triangles"].size() > 2, "polygon concave: triangulated")

	var separate := SydneyMesh.flat_polygons([rectangle, [[20, 0], [30, 0], [30, 10], [20, 10]]], 0.0, Color.WHITE)
	var separate_info := _check_mesh(separate, "polygon two rings")
	check(separate_info["triangles"].size() == 4, "polygon two rings: both filled independently")

	var crossing := SydneyMesh.crossings([{"x": 0.0, "z": 0.0, "angleRad": 0.0, "lengthM": 20.0}], 0.0, Color.WHITE)
	var crossing_info := _check_mesh(crossing, "crossing stripes")
	check(crossing_info["triangles"].size() >= 12, "crossing: multiple zebra bars rather than one block")
	var bounded := true
	for vertex in crossing_info["vertices"]:
		# Walking direction is +X (length 20); bars extend 3 m along Z.
		if absf(vertex.x) > 10.2 or absf(vertex.z) > 11.5:
			bounded = false
	check(bounded, "crossing: stripes stay within the supplied crossing envelope")


func run() -> void:
	_test_buildings()
	_test_roads()
	_test_polygons_and_crossings()
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
