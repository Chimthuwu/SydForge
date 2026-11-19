extends SceneTree

## Focused checks for the Phase 6B CBD facade builder.
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##     --script res://tests/cbd_geometry_test.gd

var checks := 0
var failures := 0
const Builder := preload("res://sydney/cbd/cbd_buildings.gd")


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _initialize() -> void:
	call_deferred("run")


func _row(ring: Array, height: float, style: String, id: String) -> Dictionary:
	return {"id": id, "ring": ring, "heightM": height, "style": style}


func _info(mesh: ArrayMesh) -> Dictionary:
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
			triangles.append([vertices[indices[index]], vertices[indices[index + 1]], vertices[indices[index + 2]],
				normals[indices[index]]])
	else:
		for index in range(0, vertices.size(), 3):
			triangles.append([vertices[index], vertices[index + 1], vertices[index + 2], normals[index]])
	return {"vertices": vertices, "normals": normals, "triangles": triangles}


func _checksum(mesh: ArrayMesh) -> int:
	var total := 0
	for point in _info(mesh)["vertices"]:
		total = (total * 31 + roundi(point.x * 100.0) + roundi(point.y * 100.0) * 7 + roundi(point.z * 100.0) * 13) % 1000000007
	return total


func _build(rows: Array) -> Dictionary:
	var builder = Builder.new()
	var result: Dictionary = builder.build(rows, Vector3.ZERO)
	var mesh: ArrayMesh = result.get("mesh")
	return {"result": result, "mesh": SydneyMesh.engine_building_mesh(mesh) if mesh != null else null}


func _check_valid(mesh: ArrayMesh, label: String, ring: Array) -> Dictionary:
	var info := _info(mesh)
	check(mesh != null and mesh.get_surface_count() > 0, label + ": mesh exists")
	check(info["triangles"].size() > 0, label + ": has triangles")
	var finite := true
	for point in info["vertices"]:
		if is_nan(point.x) or is_nan(point.y) or is_nan(point.z) \
			or is_inf(point.x) or is_inf(point.y) or is_inf(point.z):
			finite = false
	check(finite, label + ": all vertices finite")
	var unit_normals := true
	for normal in info["normals"]:
		if absf(normal.length() - 1.0) > 0.01:
			unit_normals = false
	check(unit_normals, label + ": all normals unit length")
	var degenerate := 0
	var wrong_winding := 0
	for triangle in info["triangles"]:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var cross := (b - a).cross(c - a)
		if cross.length() < 1e-6:
			degenerate += 1
			continue
		var normal: Vector3 = triangle[3]
		# Engine convention: front faces are clockwise about the stored normal.
		if cross.dot(normal) >= 0.0:
			wrong_winding += 1
	check(degenerate == 0, label + ": no degenerate triangles")
	check(wrong_winding == 0, label + ": clockwise engine winding about every normal")
	# Nothing may stick out of the parcel more than the authored cornice lip.
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in ring:
		min_x = minf(min_x, float(point[0]))
		max_x = maxf(max_x, float(point[0]))
		min_z = minf(min_z, float(point[1]))
		max_z = maxf(max_z, float(point[1]))
	var outside := 0
	for point in info["vertices"]:
		if point.x < min_x - 0.45 or point.x > max_x + 0.45 or point.z < min_z - 0.45 or point.z > max_z + 0.45:
			outside += 1
	check(outside == 0, label + ": facade stays within the parcel envelope")
	var lowest := INF
	for point in info["vertices"]:
		lowest = minf(lowest, point.y)
	check(absf(lowest) < 0.02, label + ": building sits on the ground plane")
	return info


func run() -> void:
	var rectangle := [[0, 0], [20, 0], [20, 14], [0, 14]]
	var styles := {
		"glass-tower": 120.0, "stone-commercial": 46.0, "brick-commercial": 18.0,
		"retail": 20.0, "terrace": 11.0, "sandstone": 12.0,
		"warehouse": 14.0, "apartment": 34.0,
	}
	var totals: Dictionary = {}
	for style in styles:
		var built := _build([_row(rectangle, styles[style], style, "test/" + style)])
		var info := _check_valid(built["mesh"], "style " + style, rectangle)
		var stats: Dictionary = built["result"]["stats"]
		check(int(stats.get("built", 0)) == 1, "style " + style + ": one building built")
		check(int(stats.get("degenerateTriangles", 0)) == 0, "style " + style + ": builder rejects no degenerates")
		totals[style] = info["triangles"].size()
	print("TRIANGLES BY STYLE: ", totals)

	# A tall tower must produce a podium/tower split; a low terrace must not.
	# The parcel is 40 x 30 m, which is the scale a 140 m tower actually occupies
	# (the export caps a building's height by its parcel area for this reason).
	var tower_parcel := [[0, 0], [40, 0], [40, 30], [0, 30]]
	var tower := _build([_row(tower_parcel, 140.0, "glass-tower", "test/tower")])
	check(int(tower["result"]["stats"].get("detachedPodiums", 0)) == 1, "tall tower gets a podium and setback shaft")
	_check_valid(tower["mesh"], "style glass-tower tower parcel", tower_parcel)
	var low := _build([_row(rectangle, 10.0, "terrace", "test/low")])
	check(int(low["result"]["stats"].get("detachedPodiums", 0)) == 0, "low terrace has no podium split")

	# Determinism and per-building variation.
	var first := _build([_row(rectangle, 34.0, "stone-commercial", "test/a")])
	var second := _build([_row(rectangle, 34.0, "stone-commercial", "test/a")])
	var third := _build([_row(rectangle, 34.0, "stone-commercial", "test/b")])
	check(_checksum(first["mesh"]) == _checksum(second["mesh"]), "facade build is deterministic")
	check(_checksum(first["mesh"]) != _checksum(third["mesh"]), "different ids produce different buildings")

	# Collision triangles must equal rendered triangles.
	var info := _info(first["mesh"])
	var faces: PackedVector3Array = first["result"]["faces"]
	check(faces.size() / 3 == info["triangles"].size(), "collision triangles match rendered triangles")

	# Invalid input must be rejected, not emitted half-built.
	var flat := _build([_row([[0, 0], [10, 0], [20, 0]], 20.0, "stone-commercial", "test/flat")])
	check(int(flat["result"]["stats"].get("built", 0)) == 0, "collinear footprint rejected")
	var tiny := _build([_row([[0, 0], [0.3, 0], [0.3, 0.3], [0, 0.3]], 20.0, "retail", "test/tiny")])
	check(int(tiny["result"]["stats"].get("built", 0)) == 0, "degenerate 0.09 m2 parcel rejected")

	# An L-shaped parcel must keep every wall outward-facing and stay valid.
	var l_shape := [[0, 0], [0, 18], [7, 18], [7, 8], [18, 8], [18, 0]]
	var shaped := _build([_row(l_shape, 28.0, "brick-commercial", "test/L")])
	_check_valid(shaped["mesh"], "concave L parcel", l_shape)

	# A deep, narrow terrace parcel (real Surry Hills geometry).
	var narrow := [[0, 0], [0, 6.2], [17.0, 6.2], [17.0, 0]]
	var terrace := _build([_row(narrow, 9.6, "terrace", "test/terrace")])
	var terrace_info := _check_valid(terrace["mesh"], "narrow terrace parcel", narrow)
	check(terrace_info["triangles"].size() < 120, "narrow terrace stays cheap")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
