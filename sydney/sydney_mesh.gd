class_name SydneyMesh
extends RefCounted

## Geometry builders for the Sydney world importer.
##
## All geometry is metres with Y up. Stage A polygons are outer rings only
## (verified: no `holes` field in buildings, parks or water), so flat_polygons()
## treats every ring as an independent filled polygon. It is not a
## hole-triangulation API; callers with holes must split/bridge them first.
##
## Flat surfaces (roads, parks, water) use disabled culling because they are
## single-sided planes seen from both sides. Buildings now use correct winding
## and back-face culling; their normals come from signed area, not the centroid.

const EPSILON := 0.000001
const MITER_LIMIT := 2.5
const CROSSING_BAR_LENGTH := 3.0
const CROSSING_BAR_WIDTH := 0.55
const CROSSING_BAR_GAP := 0.55

static var _cache: Dictionary = {}


static func mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = material
	return material


static func vertex_mat() -> StandardMaterial3D:
	if _cache.has("__vertex__"):
		return _cache["__vertex__"]
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_cache["__vertex__"] = material
	return material


# ---------------------------------------------------------------- utilities --
static func _finite(value: float) -> bool:
	return not (is_nan(value) or is_inf(value))


static func _finite_vec(point: Vector2) -> bool:
	return _finite(point.x) and _finite(point.y)


static func _clean_points(raw: Array) -> Array:
	"""Drop non-finite and consecutive duplicate points. Keeps loop closure."""
	var out: Array = []
	for item in raw:
		var point := Vector2(float(item[0]), float(item[1]))
		if not _finite_vec(point):
			continue
		if out.is_empty() or out[-1].distance_to(point) > 0.0001:
			out.append(point)
	return out


static func _clean_path_points(raw: Array) -> Array:
	"""Drop near-zero edges before segment normals are built.

	Without this, one sub-millimetre segment makes the segment/normal counts
	disagree and silently drops the whole road or footpath. Rings keep the finer
	1e-4 m tolerance because a tiny ring is rejected as degenerate anyway.
	"""
	var points := _clean_points(raw)
	var out: Array = []
	for point in points:
		if out.is_empty() or out[-1].distance_to(point) >= 0.001:
			out.append(point)
	return out


static func _clean_ring(raw: Array) -> PackedVector2Array:
	"""Clean a polygon ring: no repeated closing vertex, no duplicate neighbours."""
	var points := _clean_points(raw)
	if points.size() > 1 and points[0].distance_to(points[-1]) <= 0.0001:
		points.pop_back()
	var packed := PackedVector2Array()
	for point in points:
		packed.append(point)
	return packed


static func _signed_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


static func _perp(direction: Vector2) -> Vector2:
	return Vector2(-direction.y, direction.x)


static func _add_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	color: Color,
) -> PackedVector3Array:
	"""Add a non-degenerate triangle, orienting its winding to `normal`.

	Returns the three oriented vertices so collision can use exactly the same
	triangles as the rendered mesh. Empty means the triangle was degenerate.
	"""
	var cross := (b - a).cross(c - a)
	if cross.length() < EPSILON:
		return PackedVector3Array()
	if cross.dot(normal) < 0.0:
		var swap := b
		b = c
		c = swap
	surface.set_normal(normal)
	surface.set_color(color)
	surface.add_vertex(a)
	surface.set_normal(normal)
	surface.set_color(color)
	surface.add_vertex(b)
	surface.set_normal(normal)
	surface.set_color(color)
	surface.add_vertex(c)
	return PackedVector3Array([a, b, c])


# -------------------------------------------------------------- flat paths --
static func flat_paths(paths: Array, widths: Array, y: float, color: Color) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in paths.size():
		var path: Array = paths[index]
		var width: float = float(widths[index]) if index < widths.size() else 2.0
		_add_path(surface, path, width, y)
	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat(color))
	return mesh


static func _add_path(surface: SurfaceTool, path: Array, width: float, y: float) -> void:
	var points := _clean_path_points(path)
	if points.size() < 2:
		return
	var half := maxf(width, 0.2) * 0.5
	var segment_normals: Array = []
	for index in range(points.size() - 1):
		var direction: Vector2 = points[index + 1] - points[index]
		if direction.length() < 0.001:
			continue
		segment_normals.append(_perp(direction.normalized()))
	# _clean_path_points guarantees a 1:1 segment/normal mapping; this remains a
	# defensive guard for any future caller that bypasses it.
	if segment_normals.size() != points.size() - 1:
		push_error("SydneyMesh: path segment/normal count mismatch; path skipped")
		return

	var join_normals: Array = []
	var miter_ok: Array = []
	for index in points.size():
		join_normals.append(segment_normals[clampi(index, 0, segment_normals.size() - 1)])
		miter_ok.append(false)
	for index in range(1, points.size() - 1):
		var previous: Vector2 = segment_normals[index - 1]
		var current: Vector2 = segment_normals[index]
		var combined := previous + current
		if combined.length() < 0.01:
			continue
		var miter := combined.normalized()
		var dot := miter.dot(previous)
		if dot < 0.38:
			continue
		var scale := 1.0 / dot
		if scale > MITER_LIMIT:
			continue
		join_normals[index] = miter
		miter_ok[index] = true

	for index in range(points.size() - 1):
		var start_normal: Vector2 = segment_normals[index]
		var end_normal: Vector2 = segment_normals[index]
		if index > 0 and miter_ok[index]:
			start_normal = join_normals[index]
		if index + 1 < points.size() - 1 and miter_ok[index + 1]:
			end_normal = join_normals[index + 1]
		_add_ribbon_quad(surface, points[index], points[index + 1], start_normal, end_normal, half, y)

	# Bevel joins: connect the previous segment's end cross-section to the next
	# segment's start cross-section. This avoids long miter spikes at acute bends.
	for index in range(1, points.size() - 1):
		if miter_ok[index]:
			continue
		var previous: Vector2 = segment_normals[index - 1]
		var current: Vector2 = segment_normals[index]
		var point: Vector2 = points[index]
		var left_previous := point + previous * half
		var right_previous := point - previous * half
		var left_current := point + current * half
		var right_current := point - current * half
		_add_ribbon_quad(surface, left_previous, right_previous, right_current, left_current, half, y, false)


static func _add_ribbon_quad(
	surface: SurfaceTool,
	a: Vector2,
	b: Vector2,
	start_normal: Vector2,
	end_normal: Vector2,
	half: float,
	y: float,
	use_normals := true,
) -> void:
	# When use_normals is false the two points already ARE the left/right offsets
	# of one cross-section (bevel join); otherwise they are a centreline segment.
	var p0: Vector2
	var p1: Vector2
	var p2: Vector2
	var p3: Vector2
	if use_normals:
		p0 = a + start_normal * half
		p1 = a - start_normal * half
		p2 = b - end_normal * half
		p3 = b + end_normal * half
	else:
		p0 = a
		p1 = b
		p2 = end_normal
		p3 = start_normal
	_add_triangle(
		surface,
		Vector3(p0.x, y, p0.y),
		Vector3(p1.x, y, p1.y),
		Vector3(p2.x, y, p2.y),
		Vector3.UP,
		Color.WHITE,
	)
	_add_triangle(
		surface,
		Vector3(p0.x, y, p0.y),
		Vector3(p2.x, y, p2.y),
		Vector3(p3.x, y, p3.y),
		Vector3.UP,
		Color.WHITE,
	)


# ------------------------------------------------------------ road network --
static func road_mesh(roads: Array, junctions: Array, y: float, color: Color) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var by_id: Dictionary = {}
	for road in roads:
		if bool(road.get("tunnel", false)):
			continue
		var path: Array = []
		for point in road.get("points", []):
			path.append(Vector2(float(point[0]), float(point[1])))
		if path.size() < 2:
			continue
		by_id[str(road.get("id", ""))] = road
		_add_path(surface, path, float(road.get("widthM", 8.0)), y)
	for junction in junctions:
		if int(junction.get("roadCount", 0)) < 3:
			continue
		_add_junction(surface, junction, by_id, y - 0.004)
	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat(color))
	return mesh


static func _add_junction(surface: SurfaceTool, junction: Dictionary, by_id: Dictionary, y: float) -> void:
	var center := Vector2(float(junction.get("x", 0.0)), float(junction.get("z", 0.0)))
	var corners := PackedVector2Array()
	for road_id in junction.get("roadIds", []):
		var road: Dictionary = by_id.get(str(road_id), {})
		if road.is_empty():
			continue
		var hit := _nearest_segment(road.get("points", []), center)
		if hit.is_empty():
			continue
		var point: Vector2 = hit["point"]
		var direction: Vector2 = hit["direction"]
		var normal := _perp(direction)
		var half := float(road.get("widthM", 8.0)) * 0.5
		corners.append(point + normal * half)
		corners.append(point - normal * half)
	if corners.size() < 4:
		return
	var hull := Geometry2D.convex_hull(corners)
	if hull.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(hull)
	if indices.is_empty():
		return
	for index in range(0, indices.size(), 3):
		var a := hull[indices[index]]
		var b := hull[indices[index + 1]]
		var c := hull[indices[index + 2]]
		_add_triangle(
			surface,
			Vector3(a.x, y, a.y),
			Vector3(b.x, y, b.y),
			Vector3(c.x, y, c.y),
			Vector3.UP,
			Color.WHITE,
		)


static func _nearest_segment(points: Array, target: Vector2) -> Dictionary:
	var best := {}
	var best_distance := INF
	for index in range(points.size() - 1):
		var a := Vector2(float(points[index][0]), float(points[index][1]))
		var b := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
		var direction := b - a
		var length_sq := direction.length_squared()
		if length_sq < 0.0001:
			continue
		var t := clampf((target - a).dot(direction) / length_sq, 0.0, 1.0)
		var point := a + direction * t
		var distance := point.distance_to(target)
		if distance < best_distance:
			best_distance = distance
			best = {"point": point, "direction": direction.normalized(), "distance": distance}
	return best


# ------------------------------------------------------------- flat polygons --
static func flat_polygons(rings: Array, y: float, color: Color) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rings:
		var points := _clean_ring(ring)
		if points.size() < 3:
			continue
		if absf(_signed_area(points)) < 0.5:
			continue
		var indices := Geometry2D.triangulate_polygon(points)
		if indices.is_empty():
			continue
		for index in range(0, indices.size(), 3):
			var a := points[indices[index]]
			var b := points[indices[index + 1]]
			var c := points[indices[index + 2]]
			_add_triangle(
				surface,
				Vector3(a.x, y, a.y),
				Vector3(b.x, y, b.y),
				Vector3(c.x, y, c.y),
				Vector3.UP,
				Color.WHITE,
			)
	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat(color))
	return mesh


# ---------------------------------------------------------------- crossings --
static func crossings(rows: Array, y: float, color: Color) -> ArrayMesh:
	"""Provisional junction crossings drawn as spaced zebra bars.

	The exporter supplies a crossing centre, a walking direction and a length
	equal to the road width. Bars run parallel to the road (perpendicular to the
	walking direction), which is the conventional zebra layout. Dimensions are
	presentation assumptions, not surveyed markings.
	"""
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rows:
		var center := Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0)))
		var angle := float(row.get("angleRad", 0.0))
		var length := maxf(float(row.get("lengthM", 3.0)), 0.5)
		var walking := Vector2(cos(angle), sin(angle))
		var along_road := _perp(walking)
		var step := CROSSING_BAR_WIDTH + CROSSING_BAR_GAP
		var count := maxi(1, int(floor((length - CROSSING_BAR_GAP) / step)))
		var start := -float(count - 1) * step * 0.5
		for index in count:
			var bar_center := center + walking * (start + float(index) * step)
			var p0 := bar_center - along_road * (CROSSING_BAR_LENGTH * 0.5) - walking * (CROSSING_BAR_WIDTH * 0.5)
			var p1 := bar_center + along_road * (CROSSING_BAR_LENGTH * 0.5) - walking * (CROSSING_BAR_WIDTH * 0.5)
			var p2 := bar_center + along_road * (CROSSING_BAR_LENGTH * 0.5) + walking * (CROSSING_BAR_WIDTH * 0.5)
			var p3 := bar_center - along_road * (CROSSING_BAR_LENGTH * 0.5) + walking * (CROSSING_BAR_WIDTH * 0.5)
			if not _finite_vec(p0 + p1 + p2 + p3):
				continue
			_add_triangle(surface, Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p1.y), Vector3(p2.x, y, p2.y), Vector3.UP, Color.WHITE)
			_add_triangle(surface, Vector3(p0.x, y, p0.y), Vector3(p2.x, y, p2.y), Vector3(p3.x, y, p3.y), Vector3.UP, Color.WHITE)
	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat(color))
	return mesh


# ---------------------------------------------------------------- buildings --
static func buildings(rows: Array) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var built := 0
	var skipped := 0
	var degenerate_triangles := 0
	for row in rows:
		var points := _clean_ring(row.get("ring", []))
		if points.size() < 3:
			skipped += 1
			continue
		var area := _signed_area(points)
		if absf(area) < 0.5:
			skipped += 1
			continue
		var orientation := 1.0 if area > 0.0 else -1.0
		var indices := Geometry2D.triangulate_polygon(points)
		if indices.is_empty():
			skipped += 1
			continue

		var height := clampf(float(row.get("heightM", 8.0)), 1.0, 500.0)
		var base := _building_color(row)
		var roof := base.darkened(0.28)

		# Validate the roof before writing walls, so a bad polygon cannot leave a
		# roofless shell in the mesh.
		var roof_triangles: Array = []
		for index in range(0, indices.size(), 3):
			var a := points[indices[index]]
			var b := points[indices[index + 1]]
			var c := points[indices[index + 2]]
			if absf((b - a).cross(c - a)) < EPSILON:
				degenerate_triangles += 1
				continue
			roof_triangles.append([a, b, c])
		if roof_triangles.is_empty():
			skipped += 1
			continue

		var wall_triangles := 0
		for index in points.size():
			var a := points[index]
			var b := points[(index + 1) % points.size()]
			var edge := b - a
			if edge.length() < 0.0001:
				continue
			# Signed area gives a dependable outward direction for convex AND
			# concave rings. No centroid test is involved.
			var outward := Vector2(edge.y, -edge.x).normalized() * orientation
			var normal := Vector3(outward.x, 0.0, outward.y)
			var p0 := Vector3(a.x, 0.0, a.y)
			var p1 := Vector3(b.x, 0.0, b.y)
			var p2 := Vector3(b.x, height, b.y)
			var p3 := Vector3(a.x, height, a.y)
			var first := _add_triangle(surface, p0, p1, p2, normal, base)
			if first.size() == 3:
				faces.append_array(first)
				wall_triangles += 1
			else:
				degenerate_triangles += 1
			var second := _add_triangle(surface, p0, p2, p3, normal, base)
			if second.size() == 3:
				faces.append_array(second)
				wall_triangles += 1
			else:
				degenerate_triangles += 1

		for triangle in roof_triangles:
			var a: Vector2 = triangle[0]
			var b: Vector2 = triangle[1]
			var c: Vector2 = triangle[2]
			var added := _add_triangle(
				surface,
				Vector3(a.x, height, a.y),
				Vector3(b.x, height, b.y),
				Vector3(c.x, height, c.y),
				Vector3.UP,
				roof,
			)
			if added.size() == 3:
				faces.append_array(added)
		if wall_triangles == 0:
			skipped += 1
			continue
		built += 1

	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, vertex_mat())
	return {
		"mesh": mesh,
		"faces": faces,
		"built": built,
		"skipped": skipped,
		"degenerateTriangles": degenerate_triangles,
		"triangles": faces.size() / 3,
	}


static func engine_building_mesh(mesh: ArrayMesh) -> ArrayMesh:
	# The geometry API (and its outward-normal tests) uses mathematical CCW.
	# Convert at the engine boundary to Godot clockwise front faces. Normals
	# and triangle positions are unchanged; shadows then use the exterior too.
	var result := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var indices := PackedInt32Array()
		for vertex in range(0, arrays[Mesh.ARRAY_VERTEX].size(), 3):
			indices.append_array(PackedInt32Array([vertex, vertex + 2, vertex + 1]))
		arrays[Mesh.ARRAY_INDEX] = indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(i, mesh.surface_get_material(i))
	return result


static func engine_building_faces(faces: PackedVector3Array) -> PackedVector3Array:
	var result := faces.duplicate()
	for i in range(0, result.size(), 3):
		result[i + 1] = faces[i + 2]
		result[i + 2] = faces[i + 1]
	return result


static func _building_color(row: Dictionary) -> Color:
	var palette: Array[Color] = [
		Color("c9b79a"), Color("b7a58c"), Color("d8c7a8"), Color("a9b4b8"),
		Color("c2a48e"), Color("9fa8a3"), Color("d0b49b"), Color("b9a7a0"),
	]
	var height := float(row.get("heightM", 8.0))
	if height > 55.0:
		return Color("8fa3ad")
	var key := str(row.get("id", ""))
	return palette[absi(key.hash()) % palette.size()]
