class_name InnerWestMesh
extends RefCounted

## Terrain-aware geometry builders for the Inner West district (Phase 6C).
##
## Unlike the flat Stage A builders in sydney_mesh.gd, every surface here is
## draped over the district height grid: roads, footpaths, parks, buildings and
## trees all sample the same grid, so the world is internally consistent and
## the Balmain ridge, the Rozelle ridges and the Glebe flats read as real
## terrain instead of one flat plane.
##
## Winding: triangles are emitted CLOCKWISE when viewed from the front-face
## side, which is Godot's front-face convention (see the Phase 2 winding
## correction). Collision faces use exactly the same vertex order as the
## rendered triangles, so render and physics can never disagree.


const EPSILON := 0.000001
const MITER_LIMIT := 2.5

static var _cache: Dictionary = {}


# ------------------------------------------------------------- materials --
static func mat(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var key := "%s#%s" % [color.to_html(), roughness]
	if _cache.has(key):
		return _cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
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


# ---------------------------------------------------------- triangle core --
## Add one clockwise-front triangle. Returns the 3 points in emitted order for
## collision parity, or an empty array if the triangle is degenerate.
static func tri(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	color: Color,
) -> PackedVector3Array:
	var cross := (b - a).cross(c - a)
	if cross.length() < EPSILON:
		return PackedVector3Array()
	if cross.dot(normal) > 0.0:
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


static func commit(surface: SurfaceTool, material: Material) -> ArrayMesh:
	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	return mesh


# ------------------------------------------------------------ height grid --
## The grid dictionary: {data: PackedFloat32Array, nx, nz, minX, minZ,
## spacing, hMin, hMax}. Rows run north (minZ) to south; columns west to east.
static func load_height_grid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("InnerWestMesh: height grid missing: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var data := PackedFloat32Array()
	data.resize(bytes.size() / 4)
	for index in data.size():
		data[index] = bytes.decode_float(index * 4)
	return {
		"data": data,
	}


static func grid_from_meta(data: PackedFloat32Array, meta: Dictionary) -> Dictionary:
	return {
		"data": data,
		"nx": int(meta.get("nx", 0)),
		"nz": int(meta.get("nz", 0)),
		"minX": float(meta.get("minX", 0.0)),
		"minZ": float(meta.get("minZ", 0.0)),
		"spacing": float(meta.get("spacingM", 16.0)),
		"hMin": float(meta.get("hMin", 0.0)),
		"hMax": float(meta.get("hMax", 0.0)),
	}


static func height_at(grid: Dictionary, x: float, z: float) -> float:
	var nx: int = grid.get("nx", 0)
	var nz: int = grid.get("nz", 0)
	if nx < 2 or nz < 2:
		return 0.0
	var spacing: float = grid["spacing"]
	var fx := (x - float(grid["minX"])) / spacing
	var fz := (z - float(grid["minZ"])) / spacing
	var col := clampi(int(floor(fx)), 0, nx - 2)
	var row := clampi(int(floor(fz)), 0, nz - 2)
	var tx := clampf(fx - col, 0.0, 1.0)
	var tz := clampf(fz - row, 0.0, 1.0)
	var data: PackedFloat32Array = grid["data"]
	var h00 := data[row * nx + col]
	var h10 := data[row * nx + col + 1]
	var h01 := data[(row + 1) * nx + col]
	var h11 := data[(row + 1) * nx + col + 1]
	return (
		h00 * (1.0 - tx) * (1.0 - tz)
		+ h10 * tx * (1.0 - tz)
		+ h01 * (1.0 - tx) * tz
		+ h11 * tx * tz
	)


static func height_along(grid: Dictionary, points: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(points.size())
	for index in points.size():
		var point: Array = points[index]
		out[index] = height_at(grid, float(point[0]), float(point[1]))
	return out


## Terrain normal from central differences (smoothed by the grid itself).
static func terrain_normal_at(grid: Dictionary, x: float, z: float) -> Vector3:
	var spacing: float = grid.get("spacing", 16.0)
	var h_x0 := height_at(grid, x - spacing, z)
	var h_x1 := height_at(grid, x + spacing, z)
	var h_z0 := height_at(grid, x, z - spacing)
	var h_z1 := height_at(grid, x, z + spacing)
	var normal := Vector3(h_x0 - h_x1, 2.0 * spacing, h_z0 - h_z1)
	return normal.normalized()


# ---------------------------------------------------------------- terrain --
## One render mesh for the whole district plus per-chunk collision faces.
## Vertex colour varies with height: seabed, sand near the waterline, dry
## grass higher up, so the shoreline reads even before parks are drawn.
static func terrain_mesh(grid: Dictionary, chunks: int = 8) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx: int = grid["nx"]
	var nz: int = grid["nz"]
	var spacing: float = grid["spacing"]
	var min_x: float = grid["minX"]
	var min_z: float = grid["minZ"]
	var data: PackedFloat32Array = grid["data"]

	var chunk_faces: Array = []
	for index in chunks * chunks:
		chunk_faces.append(PackedVector3Array())

	var rows_per_chunk := int(ceil(float(nz - 1) / chunks))
	var cols_per_chunk := int(ceil(float(nx - 1) / chunks))

	for row in nz - 1:
		for col in nx - 1:
			var x0 := min_x + col * spacing
			var z0 := min_z + row * spacing
			var x1 := x0 + spacing
			var z1 := z0 + spacing
			var h00 := data[row * nx + col]
			var h10 := data[row * nx + col + 1]
			var h01 := data[(row + 1) * nx + col]
			var h11 := data[(row + 1) * nx + col + 1]
			var a := Vector3(x0, h00, z0)
			var b := Vector3(x1, h10, z0)
			var c := Vector3(x1, h11, z1)
			var d := Vector3(x0, h01, z1)
			var normal := (b - a).cross(d - a)
			if normal.y < 0.0:
				normal = -normal
			normal = normal.normalized()
			var color := _terrain_color((h00 + h10 + h01 + h11) * 0.25)
			var faces := _tri(surface, a, b, c, normal, color)
			# diagonal consistently along a->d so joins stay watertight
			var faces2 := _tri(surface, a, c, d, normal, color)
			var chunk_row := mini(row / rows_per_chunk, chunks - 1)
			var chunk_col := mini(col / cols_per_chunk, chunks - 1)
			var target: PackedVector3Array = chunk_faces[chunk_row * chunks + chunk_col]
			target.append_array(faces)
			target.append_array(faces2)
	var mesh := commit(surface, vertex_mat())
	return {"mesh": mesh, "chunkFaces": chunk_faces, "chunks": chunks}


static func _terrain_color(height: float) -> Color:
	if height < -1.0:
		return Color("3c5a63")
	if height < 0.2:
		var t := clampf((height + 1.0) / 1.2, 0.0, 1.0)
		return Color("8f8871").lerp(Color("7a8468"), t)
	if height < 3.0:
		return Color("7a8468").lerp(Color("6f8158"), (height - 0.2) / 2.8)
	return Color("6f8158").lerp(Color("77855c"), clampf((height - 3.0) / 60.0, 0.0, 1.0))


# ------------------------------------------------------------ flat/draped --
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
			var a := points[int(indices[index])]
			var b := points[int(indices[index + 1])]
			var c := points[int(indices[index + 2])]
			_tri(
				surface,
				Vector3(a.x, y, a.y),
				Vector3(b.x, y, b.y),
				Vector3(c.x, y, c.y),
				Vector3.UP,
				Color.WHITE,
			)
	return commit(surface, mat(color))


## Polygons lifted to the height grid (parks, pitches, reserves).
static func draped_polygons(grid: Dictionary, rings: Array, y_offset: float, color: Color) -> ArrayMesh:
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
			var a := points[int(indices[index])]
			var b := points[int(indices[index + 1])]
			var c := points[int(indices[index + 2])]
			var ya := height_at(grid, a.x, a.y) + y_offset
			var yb := height_at(grid, b.x, b.y) + y_offset
			var yc := height_at(grid, c.x, c.y) + y_offset
			var normal := (
				Vector3(b.x - a.x, yb - ya, b.y - a.y)
				. cross(Vector3(c.x - a.x, yc - ya, c.y - a.y))
			)
			if normal.y < 0.0:
				normal = -normal
			_tri(
				surface,
				Vector3(a.x, ya, a.y),
				Vector3(b.x, yb, b.y),
				Vector3(c.x, yc, c.y),
				normal.normalized(),
				Color.WHITE,
			)
	return commit(surface, mat(color))


# ---------------------------------------------------------------- ribbons --
## Terrain-following ribbons for roads, footpaths and rail ballast.
## `ys` (optional) overrides terrain heights point-by-point (bridge decks).
static func draped_paths(
	grid: Dictionary,
	paths: Array,
	widths: Array,
	y_offset: float,
	color: Color,
	ys: Array = [],
) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in paths.size():
		var path: Array = paths[index]
		var width: float = float(widths[index]) if index < widths.size() else 2.0
		var override: PackedFloat32Array = ys[index] if index < ys.size() else PackedFloat32Array()
		_add_draped_path(surface, grid, path, width, y_offset, override)
	return commit(surface, mat(color))


static func _add_draped_path(
	surface: SurfaceTool,
	grid: Dictionary,
	raw_path: Array,
	width: float,
	y_offset: float,
	override: PackedFloat32Array,
) -> void:
	var points := _clean_path_points(raw_path)
	if points.size() < 2:
		return
	var half := maxf(width, 0.2) * 0.5

	var ys := PackedFloat32Array()
	ys.resize(points.size())
	for index in points.size():
		if index < override.size():
			ys[index] = override[index] + y_offset
		else:
			ys[index] = height_at(grid, points[index].x, points[index].y) + y_offset

	var segment_normals: Array = []
	for index in range(points.size() - 1):
		var direction: Vector2 = points[index + 1] - points[index]
		if direction.length() < 0.001:
			continue
		segment_normals.append(_perp(direction.normalized()))
	if segment_normals.size() != points.size() - 1:
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
		_draped_quad(
			surface, grid, points[index], points[index + 1],
			start_normal, end_normal, half, ys[index], ys[index + 1],
		)
	for index in range(1, points.size() - 1):
		if miter_ok[index]:
			continue
		var previous: Vector2 = segment_normals[index - 1]
		var current: Vector2 = segment_normals[index]
		var point: Vector2 = points[index]
		var y := ys[index]
		var left_previous := _lifted(point + previous * half, y)
		var right_previous := _lifted(point - previous * half, y)
		var left_current := _lifted(point + current * half, y)
		var right_current := _lifted(point - current * half, y)
		var normal := Vector3.UP
		_tri(surface, left_previous, right_previous, right_current, normal, Color.WHITE)
		_tri(surface, left_previous, right_current, left_current, normal, Color.WHITE)


static func _lifted(point: Vector2, y: float) -> Vector3:
	return Vector3(point.x, y, point.y)


static func _draped_quad(
	surface: SurfaceTool,
	grid: Dictionary,
	a: Vector2,
	b: Vector2,
	start_normal: Vector2,
	end_normal: Vector2,
	half: float,
	ya: float,
	yb: float,
) -> void:
	var p0 := Vector3(a.x + start_normal.x * half, ya, a.y + start_normal.y * half)
	var p1 := Vector3(a.x - start_normal.x * half, ya, a.y - start_normal.y * half)
	var p2 := Vector3(b.x - end_normal.x * half, yb, b.y - end_normal.y * half)
	var p3 := Vector3(b.x + end_normal.x * half, yb, b.y + end_normal.y * half)
	var normal := Vector3.UP
	_tri(surface, p0, p1, p2, normal, Color.WHITE)
	_tri(surface, p0, p2, p3, normal, Color.WHITE)


## Junction patches lifted to the terrain at their kerb corners.
static func draped_junctions(
	grid: Dictionary,
	junctions: Array,
	roads_by_id: Dictionary,
	y_offset: float,
	color: Color,
) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for junction in junctions:
		if int(junction.get("roadCount", 0)) < 3:
			continue
		var center := Vector2(float(junction.get("x", 0.0)), float(junction.get("z", 0.0)))
		var corners := PackedVector2Array()
		for road_id in junction.get("roadIds", []):
			var road: Dictionary = roads_by_id.get(str(road_id), {})
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
			continue
		var hull := Geometry2D.convex_hull(corners)
		if hull.size() < 3:
			continue
		var indices := Geometry2D.triangulate_polygon(hull)
		if indices.is_empty():
			continue
		for index in range(0, indices.size(), 3):
			var a := hull[indices[index]]
			var b := hull[indices[index + 1]]
			var c := hull[indices[index + 2]]
			var ya := height_at(grid, a.x, a.y) + y_offset
			var yb := height_at(grid, b.x, b.y) + y_offset
			var yc := height_at(grid, c.x, c.y) + y_offset
			_tri(
				surface,
				Vector3(a.x, ya, a.y),
				Vector3(b.x, yb, b.y),
				Vector3(c.x, yc, c.y),
				Vector3.UP,
				Color.WHITE,
			)
	return commit(surface, mat(color))


# ---------------------------------------------------------- bridge decks --
## Deck height profile for a bridge road: terrain at the anchored ends, a
## parabolic hump to `clearance` over the water span in between.
static func bridge_deck_ys(
	grid: Dictionary,
	points: Array,
	clearance: float,
	water_y: float = -0.38,
) -> PackedFloat32Array:
	var ys := PackedFloat32Array()
	if points.size() < 2:
		return ys
	ys.resize(points.size())
	var terrain := height_along(grid, points)
	# deck must stay above both the water and the terrain
	var deck_min := maxf(water_y + clearance, 2.0)
	for index in points.size():
		var hump := 4.0 * (float(index) / float(points.size() - 1))
		hump = hump * (1.0 - hump / 4.0)  # parabola peaking at 1.0 mid-span
		var target := deck_min + clearance * 1.15 * hump
		ys[index] = maxf(terrain[index] + 0.5, target)
	# ease the last few points back to terrain so the deck lands on the shore
	var blend := mini(3, points.size() - 1)
	for side in 2:
		for step in blend:
			var index := step if side == 0 else points.size() - 1 - step
			var anchor := 0 if side == 0 else points.size() - 1
			var weight := float(blend - step) / float(blend + 1)
			ys[index] = lerpf(terrain[index], ys[index], clampf(1.0 - weight, 0.0, 1.0))
	return ys


## Solid side walls so vehicles cannot drive off a bridge deck.
static func bridge_barriers(
	road: Dictionary,
	ys: PackedFloat32Array,
	height: float = 1.1,
) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var points := _clean_path_points(road.get("points", []))
	if points.size() < 2 or points.size() != ys.size():
		return {"mesh": null, "faces": faces}
	var half := float(road.get("widthM", 8.0)) * 0.5 + 0.18
	var color := Color("b9bcc0")
	for side in [-1.0, 1.0]:
		for index in range(points.size() - 1):
			var direction: Vector2 = (points[index + 1] - points[index]).normalized()
			var normal: Vector2 = _perp(direction) * side
			var ya := ys[index]
			var yb := ys[index + 1]
			var a := Vector3(points[index].x + normal.x * half, ya, points[index].y + normal.y * half)
			var b := Vector3(points[index + 1].x + normal.x * half, yb, points[index + 1].y + normal.y * half)
			var wall_normal := Vector3(normal.x, 0.0, normal.y)
			faces.append_array(_tri(surface, a, b, b + Vector3.UP * height, wall_normal, color))
			faces.append_array(_tri(surface, a, b + Vector3.UP * height, a + Vector3.UP * height, wall_normal, color))
			# top cap
			faces.append_array(_tri(surface, a + Vector3.UP * height, b + Vector3.UP * height, Vector3(b.x, yb + height + 0.12, b.z), wall_normal, color))
	var mesh: ArrayMesh = commit(surface, mat(color)) if faces.size() >= 3 else null
	return {"mesh": mesh, "faces": faces}


# ------------------------------------------------------------- crossings --
## Zebra bars draped on the terrain (real OSM crossings + derived ones).
static func draped_crossings(
	grid: Dictionary,
	rows: Array,
	y_offset: float,
	color: Color,
	bar_length: float = 3.6,
) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rows:
		var center := Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0)))
		var angle := float(row.get("angleRad", 0.0))
		var length := maxf(float(row.get("lengthM", 3.0)), 0.5)
		var walking := Vector2(cos(angle), sin(angle))
		var along_road := _perp(walking)
		var y := height_at(grid, center.x, center.y) + y_offset
		var step := 0.55 + 0.55
		var count := maxi(1, int(floor((length - 0.55) / step)))
		var start := -float(count - 1) * step * 0.5
		for index in count:
			var bar_center := center + walking * (start + float(index) * step)
			var p0 := bar_center - along_road * (bar_length * 0.5) - walking * 0.275
			var p1 := bar_center + along_road * (bar_length * 0.5) - walking * 0.275
			var p2 := bar_center + along_road * (bar_length * 0.5) + walking * 0.275
			var p3 := bar_center - along_road * (bar_length * 0.5) + walking * 0.275
			_tri(surface, _lifted(p0, y), _lifted(p1, y), _lifted(p2, y), Vector3.UP, Color.WHITE)
			_tri(surface, _lifted(p0, y), _lifted(p2, y), _lifted(p3, y), Vector3.UP, Color.WHITE)
	return commit(surface, mat(color))


# ----------------------------------------------------------------- steps --
## Real stair geometry for OSM highway=steps: risers the player can climb with
## the existing 0.6 m step assist (risers here are <= 0.24 m).
static func steps_mesh(
	grid: Dictionary,
	raw_path: Array,
	width: float,
	color: Color,
) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var points := _clean_path_points(raw_path)
	if points.size() < 2:
		return {"mesh": null, "faces": faces}
	var total := 0.0
	for index in range(points.size() - 1):
		total += points[index].distance_to(points[index + 1])
	if total < 0.5:
		return {"mesh": null, "faces": faces}
	var y_start := height_at(grid, points[0].x, points[0].y)
	var y_end := height_at(grid, points[-1].x, points[-1].y)
	var rise := y_end - y_start
	var step_run := 0.42
	var step_rise := 0.18
	var count := maxi(2, int(ceil(maxf(absf(rise) / step_rise, total / step_run))))
	var half := maxf(width, 1.2) * 0.5
	var edge_color := color.darkened(0.12)

	# walk the polyline accumulating distance
	var walked := 0.0
	var segment := 0
	for index in count:
		var target := total * float(index) / float(count)
		while segment < points.size() - 2 and walked + points[segment].distance_to(points[segment + 1]) < target:
			walked += points[segment].distance_to(points[segment + 1])
			segment += 1
		var seg_len: float = points[segment].distance_to(points[segment + 1])
		var t := 0.0 if seg_len < 1e-6 else clampf((target - walked) / seg_len, 0.0, 1.0)
		var pos: Vector2 = points[segment].lerp(points[segment + 1], t)
		var direction: Vector2 = (points[segment + 1] - points[segment]).normalized()
		var normal := _perp(direction)
		var y_here := y_start + rise * (float(index) / float(count))
		var y_next := y_start + rise * (float(index + 1) / float(count))
		var run := total / float(count)
		var a0 := Vector3(pos.x + normal.x * half, y_here, pos.y + normal.y * half)
		var a1 := Vector3(pos.x - normal.x * half, y_here, pos.y - normal.y * half)
		var front := pos + direction * run
		var b0 := Vector3(front.x + normal.x * half, y_next, front.y + normal.y * half)
		var b1 := Vector3(front.x - normal.x * half, y_next, front.y - normal.y * half)
		# tread (slightly tilted up toward the next step)
		faces.append_array(_tri(surface, a0, a1, b1, Vector3.UP, edge_color))
		faces.append_array(_tri(surface, a0, b1, b0, Vector3.UP, edge_color))
		# riser
		var riser_normal := Vector3(-direction.x, 0.0, -direction.y)
		faces.append_array(_tri(surface, b1, a1, a0, riser_normal, color.darkened(0.25)))
		faces.append_array(_tri(surface, b1, a0, b0, riser_normal, color.darkened(0.25)))
	var mesh: ArrayMesh = commit(surface, mat(color)) if faces.size() >= 3 else null
	return {"mesh": mesh, "faces": faces}


# -------------------------------------------------------- shore barrier --
## Invisible shoreline walls following the water rings. The top adapts to the
## terrain so cliffs and reclaimed edges cannot be walked around over the wall.
static func shore_faces(
	grid: Dictionary,
	rings: Array,
	bottom_y: float = -2.0,
	wall_height: float = 2.4,
) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for ring in rings:
		var points: Array = ring
		if points.size() < 3:
			continue
		for index in points.size():
			var a: Array = points[index]
			var next: Array = points[(index + 1) % points.size()]
			var ax := float(a[0])
			var az := float(a[1])
			var bx := float(next[0])
			var bz := float(next[1])
			if Vector2(ax, az).distance_squared_to(Vector2(bx, bz)) < 0.0025:
				continue
			var ta := height_at(grid, ax, az) + wall_height
			var tb := height_at(grid, bx, bz) + wall_height
			ta = maxf(wall_height, ta)
			tb = maxf(wall_height, tb)
			faces.append(Vector3(ax, bottom_y, az))
			faces.append(Vector3(bx, bottom_y, bz))
			faces.append(Vector3(bx, tb, bz))
			faces.append(Vector3(ax, bottom_y, az))
			faces.append(Vector3(bx, tb, bz))
			faces.append(Vector3(ax, ta, az))
	return faces


# ----------------------------------------------------------------- trees --
## One stylised tree mesh (shared by a MultiMesh): 4-sided trunk + two stacked
## canopies, vertex-coloured so per-instance colour tints the whole tree.
static func tree_mesh() -> ArrayMesh:
	if _cache.has("__tree__"):
		return _cache["__tree__"]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color("8e6850")
	var canopy := Color.WHITE
	var height := 6.0
	var radius := 2.4
	# trunk: tapered box
	_add_box(surface, Vector3(0, 0, 0), Vector3(0.5, height * 0.55, 0.5), trunk)
	# lower canopy: octahedron-ish dome
	_add_pyramid(surface, Vector3(0, height * 0.45, 0), radius * 0.9, radius * 1.05, canopy)
	# upper canopy: smaller, offset for an organic silhouette
	_add_pyramid(surface, Vector3(radius * 0.25, height * 0.78, 0), radius * 0.55, radius * 0.7, canopy)
	var mesh := commit(surface, vertex_mat())
	_cache["__tree__"] = mesh
	return mesh


static func _add_box(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var corners := [
		center + Vector3(-hx, -hy, -hz), center + Vector3(hx, -hy, -hz),
		center + Vector3(hx, -hy, hz), center + Vector3(-hx, -hy, hz),
		center + Vector3(-hx, hy, -hz), center + Vector3(hx, hy, -hz),
		center + Vector3(hx, hy, hz), center + Vector3(-hx, hy, hz),
	]
	var faces := [
		[0, 1, 5, 4, Vector3(0, 0, -1)], [1, 2, 6, 5, Vector3(1, 0, 0)],
		[2, 3, 7, 6, Vector3(0, 0, 1)], [3, 0, 4, 7, Vector3(-1, 0, 0)],
		[3, 2, 6, 7, Vector3.UP], [0, 3, 7, 4, Vector3(0, 0, -1)],
	]
	# bottom face skipped (buried)
	for face_index in range(faces.size() - 1):
		var f: Array = faces[face_index]
		var normal: Vector3 = f[4]
		tri(surface, corners[f[0]], corners[f[1]], corners[f[2]], normal, color)
		tri(surface, corners[f[0]], corners[f[2]], corners[f[3]], normal, color)
	tri(surface, corners[3], corners[2], corners[6], Vector3.UP, color)
	tri(surface, corners[3], corners[6], corners[7], Vector3.UP, color)


static func _add_pyramid(surface: SurfaceTool, apex: Vector3, radius: float, height: float, color: Color) -> void:
	var base_y := apex.y - height
	var ring := PackedVector2Array()
	for index in 5:
		var angle := TAU * index / 5.0 + 0.4
		ring.append(Vector2(apex.x + cos(angle) * radius, apex.z + sin(angle) * radius))
	for index in 5:
		var a := Vector3(ring[index].x, base_y, ring[index].y)
		var b := Vector3(ring[(index + 1) % 5].x, base_y, ring[(index + 1) % 5].y)
		var normal := (b - a).cross(apex - a)
		if normal.length() < EPSILON:
			continue
		tri(surface, a, b, apex, normal.normalized(), color)
	# base disc
	for index in 5:
		var a := Vector3(ring[index].x, base_y, ring[index].y)
		var b := Vector3(ring[(index + 1) % 5].x, base_y, ring[(index + 1) % 5].y)
		tri(surface, a, b, Vector3(apex.x, base_y, apex.z), Vector3.DOWN, color)


# -------------------------------------------------------------- utilities --
static func _perp(direction: Vector2) -> Vector2:
	return Vector2(-direction.y, direction.x)


static func _clean_points(raw: Array) -> Array:
	var out: Array = []
	for item in raw:
		var point := Vector2(float(item[0]), float(item[1]))
		if out.is_empty() or out[-1].distance_to(point) > 0.0001:
			out.append(point)
	return out


static func _clean_path_points(raw: Array) -> Array:
	var points := _clean_points(raw)
	var out: Array = []
	for point in points:
		if out.is_empty() or out[-1].distance_to(point) >= 0.001:
			out.append(point)
	return out


static func _clean_ring(raw: Array) -> PackedVector2Array:
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


## Rename helper: matches the Phase 2 naming used by tests (tri is the
## canonical clockwise-front emitter; _tri mirrors it for readability).
static func _tri(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	color: Color,
) -> PackedVector3Array:
	return tri(surface, a, b, c, normal, color)


## Coarse spatial hash of road vertices, used to orient shop awnings toward
## the street. Returns {cellKey: PackedVector2Array}.
static func road_vertex_hash(roads: Array, cell: float = 64.0, stride: int = 3) -> Dictionary:
	var hash: Dictionary = {}
	for road in roads:
		var points: Array = road.get("points", [])
		for index in range(0, points.size(), stride):
			var x := float(points[index][0])
			var z := float(points[index][1])
			var key := "%d,%d" % [int(x / cell), int(z / cell)]
			if not hash.has(key):
				hash[key] = PackedVector2Array()
			hash[key].append(Vector2(x, z))
	return hash


static func nearest_road_point(hash: Dictionary, x: float, z: float, cell: float = 64.0) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	var cx := int(x / cell)
	var cz := int(z / cell)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var key := "%d,%d" % [cx + dx, cz + dz]
			if not hash.has(key):
				continue
			var points: PackedVector2Array = hash[key]
			for index in points.size():
				var distance := points[index].distance_to(Vector2(x, z))
				if distance < best_distance:
					best_distance = distance
					best = points[index]
	return best
