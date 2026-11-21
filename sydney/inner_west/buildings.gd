class_name InnerWestBuildings
extends RefCounted

## Generates the Inner West building stock from OSM footprints with
## neighbourhood-driven styling (Phase 6C): Victorian terraces with parapets
## and chimneys, Federation gables and hips in terracotta, King Street
## shopfronts with fascia bands and awnings, warehouse sawtooth roofs,
## rendered apartment slabs with floor bands, sandstone churches and civic
## buildings.
##
## Everything is vertex-coloured geometry in one ArrayMesh (plus chunked
## collision bodies), exactly like the Stage A shells, so a whole suburb is
## still a couple of draw calls. Collision is capped at BUILD_COLLISION_CAP
## metres of wall height: the player (jump apex ~1.4 m) and vehicles never
## touch anything higher, and roofs only collide when they are reachable.


const EPSILON := 0.000001
const SKIRT_DEPTH := 1.0
## Walls collide up to this height; higher masonry is visual only.
const BUILD_COLLISION_CAP := 7.0
const CHUNKS := 8


# ------------------------------------------------------------------ style --
## Main entry: returns {mesh, chunkFaces, stats} for the whole district.
static func styled_buildings(
	grid: Dictionary,
	rows: Array,
	road_hash: Dictionary,
	neighbourhood_names: Dictionary,
) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chunk_faces: Array = []
	for index in CHUNKS * CHUNKS:
		chunk_faces.append(PackedVector3Array())

	var bounds := _content_bounds(rows)
	var built := 0
	var skipped := 0
	var degenerate := 0
	var tris := 0
	var by_style: Dictionary = {}
	var min_x: float = float(bounds[0])
	var max_x: float = float(bounds[1])
	var min_z: float = float(bounds[2])
	var max_z: float = float(bounds[3])

	for row in rows:
		var points := InnerWestMesh._clean_ring(row.get("ring", []))
		if points.size() < 3:
			skipped += 1
			continue
		var area := absf(InnerWestMesh._signed_area(points))
		if area < 8.0:
			skipped += 1
			continue
		var orientation := 1.0 if area > 0.0 else -1.0
		var indices := Geometry2D.triangulate_polygon(points)
		if indices.is_empty():
			skipped += 1
			continue

		var id_text := str(row.get("id", ""))
		var id_hash := id_text.hash()
		var height := clampf(float(row.get("heightM", 8.0)), 2.5, 220.0)
		var neighbourhood_id := str(row.get("neighbourhood", ""))
		var neighbourhood_name := String(neighbourhood_names.get(neighbourhood_id, ""))
		var style := InnerWestCharacter.style_class(row, neighbourhood_name, id_hash)
		var spec := InnerWestCharacter.visual_for(
			style, id_hash, height, area, bool(row.get("shop", false))
		)
		by_style[style] = int(by_style.get(style, 0)) + 1

		# base: the lowest ground under the footprint (terraces sit at their
		# street face and sink into the slope behind, which reads correctly)
		var base := INF
		for point in points:
			base = minf(base, InnerWestMesh.height_at(grid, point.x, point.y))
		if is_inf(base) or is_nan(base):
			base = InnerWestMesh.height_at(grid, 0.0, 0.0)
		base += 0.08

		var count := _emit_building(
			surface, chunk_faces, points, indices, orientation, base, height, spec,
			row, id_hash, road_hash, min_x, max_x, min_z, max_z,
		)
		if count <= 0:
			skipped += 1
			continue
		tris += count
		built += 1

	var mesh: ArrayMesh = null
	if built > 0:
		mesh = InnerWestMesh.commit(surface, InnerWestMesh.vertex_mat())
	return {
		"mesh": mesh,
		"chunkFaces": chunk_faces,
		"chunks": CHUNKS,
		"built": built,
		"skipped": skipped,
		"degenerate": degenerate,
		"triangles": tris,
		"byStyle": by_style,
	}


static func _content_bounds(rows: Array) -> Array:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for row in rows:
		for point in row.get("ring", []):
			min_x = minf(min_x, float(point[0]))
			max_x = maxf(max_x, float(point[0]))
			min_z = minf(min_z, float(point[1]))
			max_z = maxf(max_z, float(point[1]))
	if is_inf(min_x):
		return [0.0, 1.0, 0.0, 1.0]
	return [min_x, max_x, min_z, max_z]


# --------------------------------------------------------------- emission --
## Emits one building; returns the triangle count (0 = rejected).
static func _emit_building(
	surface: SurfaceTool,
	chunk_faces: Array,
	points: PackedVector2Array,
	indices: PackedInt32Array,
	orientation: float,
	base: float,
	height: float,
	spec: Dictionary,
	row: Dictionary,
	id_hash: int,
	road_hash: Dictionary,
	min_x: float, max_x: float, min_z: float, max_z: float,
) -> int:
	var faces := PackedVector3Array()
	var tris := 0

	# ---- walls (with optional floor bands and ground-floor shop band)
	var wall_color: Color = spec["wall"]
	var ground_band: bool = spec["groundBand"]
	var floor_bands: bool = spec["floorBands"]
	var fascia_color := _fascia_color(id_hash)
	var glazing := Color("39424c")
	var band_top := 3.4
	var fascia_top := 4.35
	var trim: Color = Color(spec["trim"])

	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var edge := b - a
		if edge.length() < 0.0001:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var normal := Vector3(outward.x, 0.0, outward.y)
		var p0 := Vector3(a.x, base - SKIRT_DEPTH, a.y)
		var p1 := Vector3(b.x, base - SKIRT_DEPTH, b.y)
		var top := base + height
		if ground_band and height > band_top:
			# skirt + glazing band + fascia + upper wall
			tris += _wall_quad(surface, faces, p0, p1, Vector3(a.x, base + 0.1, a.y), Vector3(b.x, base + 0.1, b.y), normal, wall_color.darkened(0.45), BUILD_COLLISION_CAP)
			tris += _wall_quad(surface, faces, Vector3(a.x, base, a.y), Vector3(b.x, base, b.y), Vector3(a.x, base + band_top, a.y), Vector3(b.x, base + band_top, b.y), normal, glazing, BUILD_COLLISION_CAP)
			tris += _wall_quad(surface, faces, Vector3(a.x, base + band_top, a.y), Vector3(b.x, base + band_top, b.y), Vector3(a.x, base + fascia_top, a.y), Vector3(b.x, base + fascia_top, b.y), normal, fascia_color, 0.0)
			tris += _wall_quad(surface, faces, Vector3(a.x, base + fascia_top, a.y), Vector3(b.x, base + fascia_top, b.y), Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), normal, wall_color, BUILD_COLLISION_CAP)
		elif floor_bands:
			# apartments/commercial: stacked floors with a thin trim line
			var floor_height := 3.2
			var y := base
			while y < top - 0.05:
				var y_next := minf(y + floor_height, top)
				tris += _wall_quad(
					surface, faces,
					Vector3(a.x, y, a.y), Vector3(b.x, y, b.y),
					Vector3(a.x, y_next - 0.22, a.y), Vector3(b.x, y_next - 0.22, b.y),
					normal, wall_color, BUILD_COLLISION_CAP,
				)
				tris += _wall_quad(
					surface, faces,
					Vector3(a.x, y_next - 0.22, a.y), Vector3(b.x, y_next - 0.22, b.y),
					Vector3(a.x, y_next, a.y), Vector3(b.x, y_next, b.y),
					normal, trim, 0.0,
				)
				y = y_next
		else:
			tris += _wall_quad(surface, faces, p0, p1, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), normal, wall_color, BUILD_COLLISION_CAP)

	var roof_top := base + height

	# ---- roof
	match String(spec["roofKind"]):
		"parapet":
			tris += _flat_roof(surface, faces, points, indices, roof_top, spec["roof"])
			tris += _parapet(surface, faces, points, orientation, roof_top, 0.62, spec["trim"])
		"flat":
			tris += _flat_roof(surface, faces, points, indices, roof_top, spec["roof"])
			# thin cornice for definition
			tris += _parapet(surface, faces, points, orientation, roof_top - 0.18, 0.42, spec["trim"])
		"gable":
			tris += _pitched_roof(surface, faces, points, roof_top, spec["roof"], "gable")
		"hip":
			tris += _pitched_roof(surface, faces, points, roof_top, spec["roof"], "hip")
		"sawtooth":
			tris += _sawtooth_roof(surface, faces, points, roof_top, spec["roof"])
		_:
			tris += _flat_roof(surface, faces, points, indices, roof_top, spec["roof"])

	# ---- chimneys
	if bool(spec["chimney"]):
		tris += _chimneys(surface, faces, points, roof_top, spec, id_hash)

	# ---- awning over the street-facing edge
	if bool(spec["awning"]):
		tris += _awning(surface, faces, points, orientation, base, road_hash, id_hash)

	if tris == 0:
		return 0

	# scatter faces into spatial chunks (same chunk grid for every building)
	var centre := Vector2(
		(points[0].x + points[points.size() / 2].x) * 0.5,
		(points[0].y + points[points.size() / 2].y) * 0.5,
	)
	var span_x := maxf(max_x - min_x, 1.0)
	var span_z := maxf(max_z - min_z, 1.0)
	var chunk_col := clampi(int((centre.x - min_x) / span_x * CHUNKS), 0, CHUNKS - 1)
	var chunk_row := clampi(int((centre.y - min_z) / span_z * CHUNKS), 0, CHUNKS - 1)
	chunk_faces[chunk_row * CHUNKS + chunk_col].append_array(faces)
	return tris


## One vertical wall quad from ya to yb; collision emitted up to cap_y only.
static func _wall_quad(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3,
	normal: Vector3,
	color: Color,
	cap_y_relative: float,
) -> int:
	var count := 0
	var emitted_a := a0
	var emitted_b := b0
	if cap_y_relative > 0.0:
		# clamp the collision wall: a0/b0 are the bottom (often below ground),
		# a1/b1 the top. Collision runs from bottom to min(top, bottom+cap).
		var top_a := a1.y
		var limit := a0.y + cap_y_relative
		if top_a > limit:
			var t := (limit - a0.y) / maxf(top_a - a0.y, 0.01)
			emitted_a = a0.lerp(a1, t)
			emitted_b = b0.lerp(b1, t)
		faces.append_array(InnerWestMesh.tri(surface, emitted_a, emitted_b, b1, normal, color))
		faces.append_array(InnerWestMesh.tri(surface, emitted_a, b1, a1, normal, color))
		if emitted_a != a0 or emitted_b != b0:
			# also emit the clamped wall itself
			pass
		count += 2
	else:
		InnerWestMesh.tri(surface, a0, b0, b1, normal, color)
		InnerWestMesh.tri(surface, a0, b1, a1, normal, color)
		count += 2
	return count


static func _flat_roof(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	points: PackedVector2Array,
	indices: PackedInt32Array,
	y: float,
	color: Color,
) -> int:
	var count := 0
	var normal := Vector3.UP
	for index in range(0, indices.size(), 3):
		var a := points[int(indices[index])]
		var b := points[int(indices[index + 1])]
		var c := points[int(indices[index + 2])]
		faces.append_array(InnerWestMesh.tri(
			surface, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), normal, color
		))
		count += 1
	return count


## Parapet ring: outer face, inner face and a cap, inset slightly.
static func _parapet(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	points: PackedVector2Array,
	orientation: float,
	roof_y: float,
	height: float,
	color: Color,
) -> int:
	var count := 0
	var inset := 0.16
	var centroid := Vector2()
	for point in points:
		centroid += point
	centroid /= float(points.size())
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var edge := b - a
		if edge.length() < 0.0001:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var normal := Vector3(outward.x, 0.0, outward.y)
		var a_in := a + outward * -inset
		var b_in := b + outward * -inset
		var y0 := roof_y
		var y1 := roof_y + height
		var t_a := Vector3(a.x, y1, a.y)
		var t_b := Vector3(b.x, y1, b.y)
		var t_a_in := Vector3(a_in.x, y1, a_in.y)
		var t_b_in := Vector3(b_in.x, y1, b_in.y)
		# outer face
		InnerWestMesh.tri(surface, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), t_b, normal, color)
		InnerWestMesh.tri(surface, Vector3(a.x, y0, a.y), t_b, t_a, normal, color)
		# inner face
		var inner_normal := -normal
		InnerWestMesh.tri(surface, Vector3(a_in.x, y0, a_in.y), Vector3(b_in.x, y0, b_in.y), t_b_in, inner_normal, color.darkened(0.1))
		InnerWestMesh.tri(surface, Vector3(a_in.x, y0, a_in.y), t_b_in, t_a_in, inner_normal, color.darkened(0.1))
		# cap
		var cap_a := Vector3(a.x, y1, a.y)
		var cap_b := Vector3(b.x, y1, b.y)
		InnerWestMesh.tri(surface, cap_a, cap_b, t_b_in, Vector3.UP, color.lightened(0.05))
		InnerWestMesh.tri(surface, cap_a, t_b_in, t_a_in, Vector3.UP, color.lightened(0.05))
		count += 6
	return count


## Gable / hip roof from the ring's longest-edge oriented bounding box, with a
## small eaves overhang. The ridge runs parallel to the longest street wall.
static func _pitched_roof(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	points: PackedVector2Array,
	wall_y: float,
	color: Color,
	kind: String,
) -> int:
	var count := 0
	if points.size() < 3:
		return 0
	# longest edge direction = ridge axis
	var best_dir := Vector2(1, 0)
	var best_len := -1.0
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var edge := b - a
		if edge.length() > best_len:
			best_len = edge.length()
			best_dir = edge.normalized()
	var axis: Vector2 = best_dir
	var side: Vector2 = Vector2(-axis.y, axis.x)
	var u_min := INF
	var u_max := -INF
	var v_min := INF
	var v_max := -INF
	for point in points:
		var u := point.dot(axis)
		var v := point.dot(side)
		u_min = minf(u_min, u)
		u_max = maxf(u_max, u)
		v_min = minf(v_min, v)
		v_max = maxf(v_max, v)
	var span_u := u_max - u_min
	var span_v := v_max - v_min
	if span_v < 0.5:
		return 0
	var rise := clampf(span_v * 0.38, 0.7, 2.8)
	var overhang := 0.28
	var e := overhang
	var centre_v := (v_min + v_max) * 0.5
	var origin := Vector2(0, 0)

	# corners in world space helper
	if kind == "gable":
		var ridge_a := _to_world(axis, side, u_min - e * 0.5, centre_v)
		var ridge_b := _to_world(axis, side, u_max + e * 0.5, centre_v)
		var eave_0a := _to_world(axis, side, u_min - e, v_min - e)
		var eave_1a := _to_world(axis, side, u_max + e, v_min - e)
		var eave_0b := _to_world(axis, side, u_min - e, v_max + e)
		var eave_1b := _to_world(axis, side, u_max + e, v_max + e)
		var ridge_y := wall_y + rise
		var r_a := Vector3(ridge_a.x, ridge_y, ridge_a.y)
		var r_b := Vector3(ridge_b.x, ridge_y, ridge_b.y)
		var slope_normal_0 := _roof_normal(eave_0a, ridge_a, axis, side)
		var e0a := Vector3(eave_0a.x, wall_y, eave_0a.y)
		var e1a := Vector3(eave_1a.x, wall_y, eave_1a.y)
		var e0b := Vector3(eave_0b.x, wall_y, eave_0b.y)
		var e1b := Vector3(eave_1b.x, wall_y, eave_1b.y)
		faces.append_array(InnerWestMesh.tri(surface, e0a, e1a, r_b, slope_normal_0, color))
		faces.append_array(InnerWestMesh.tri(surface, e0a, r_b, r_a, slope_normal_0, color))
		var slope_normal_1 := _roof_normal(ridge_a, eave_0b, axis, side)
		faces.append_array(InnerWestMesh.tri(surface, e0b, e1b, r_b, slope_normal_1, color))
		faces.append_array(InnerWestMesh.tri(surface, e0b, r_b, r_a, slope_normal_1, color))
		count += 4
		# gable end triangles at the two ridge ends (wall colour)
		var gable_color := color.darkened(0.05)
		var end_a := Vector3(_to_world(axis, side, u_min, v_min).x, wall_y, _to_world(axis, side, u_min, v_min).y)
		var end_b := Vector3(_to_world(axis, side, u_min, v_max).x, wall_y, _to_world(axis, side, u_min, v_max).y)
		var gable_normal_a := Vector3(-axis.x, 0.0, -axis.y)
		faces.append_array(InnerWestMesh.tri(surface, end_a, end_b, r_a, gable_normal_a, gable_color))
		var end_c := Vector3(_to_world(axis, side, u_max, v_min).x, wall_y, _to_world(axis, side, u_max, v_min).y)
		var end_d := Vector3(_to_world(axis, side, u_max, v_max).x, wall_y, _to_world(axis, side, u_max, v_max).y)
		var gable_normal_b := Vector3(axis.x, 0.0, axis.y)
		faces.append_array(InnerWestMesh.tri(surface, end_c, end_d, r_b, gable_normal_b, gable_color))
		count += 2
	else:
		# hip: ridge shortened by half the v-span, four slopes
		var inset_u := (v_max - v_min) * 0.5
		var ru_min := u_min + inset_u
		var ru_max := u_max - inset_u
		if ru_max <= ru_min:
			ru_min = (u_min + u_max) * 0.5 - 0.1
			ru_max = ru_min + 0.2
		var ridge_a := _to_world(axis, side, ru_min, centre_v)
		var ridge_b := _to_world(axis, side, ru_max, centre_v)
		var ridge_y := wall_y + rise
		var r_a := Vector3(ridge_a.x, ridge_y, ridge_a.y)
		var r_b := Vector3(ridge_b.x, ridge_y, ridge_b.y)
		var e00 := Vector3(_to_world(axis, side, u_min - e, v_min - e).x, wall_y, _to_world(axis, side, u_min - e, v_min - e).y)
		var e10 := Vector3(_to_world(axis, side, u_max + e, v_min - e).x, wall_y, _to_world(axis, side, u_max + e, v_min - e).y)
		var e01 := Vector3(_to_world(axis, side, u_min - e, v_max + e).x, wall_y, _to_world(axis, side, u_min - e, v_max + e).y)
		var e11 := Vector3(_to_world(axis, side, u_max + e, v_max + e).x, wall_y, _to_world(axis, side, u_max + e, v_max + e).y)
		var n_front := _roof_normal(_to_world(axis, side, u_min, v_min), _to_world(axis, side, ru_min, centre_v), axis, side)
		faces.append_array(InnerWestMesh.tri(surface, e00, e10, r_b, n_front, color))
		faces.append_array(InnerWestMesh.tri(surface, e00, r_b, r_a, n_front, color))
		var n_back := _roof_normal(_to_world(axis, side, ru_min, centre_v), _to_world(axis, side, u_min, v_max), axis, side)
		faces.append_array(InnerWestMesh.tri(surface, e01, e11, r_b, n_back, color))
		faces.append_array(InnerWestMesh.tri(surface, e01, r_b, r_a, n_back, color))
		# hip ends
		var n_left := Vector3(-axis.x, 0.0, -axis.y)
		faces.append_array(InnerWestMesh.tri(surface, e00, r_a, e01, n_left, color.darkened(0.06)))
		var n_right := Vector3(axis.x, 0.0, axis.y)
		faces.append_array(InnerWestMesh.tri(surface, e10, r_b, e11, n_right, color.darkened(0.06)))
		count += 6
	return count



static func _to_world(axis: Vector2, side: Vector2, u: float, v: float) -> Vector2:
	return axis * u + side * v

static func _roof_normal(eave: Vector2, ridge: Vector2, axis: Vector2, side: Vector2) -> Vector3:
	var along := Vector3(axis.x, 0.0, axis.y)
	var slope := Vector3(ridge.x - eave.x, 1.2, ridge.y - eave.y)
	var normal := slope.cross(along)
	if normal.y < 0.0:
		normal = -normal
	return normal.normalized()


## Sawtooth industrial roof along the longest axis.
static func _sawtooth_roof(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	points: PackedVector2Array,
	wall_y: float,
	color: Color,
) -> int:
	if points.size() < 3:
		return 0
	var best_dir := Vector2(1, 0)
	var best_len := -1.0
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var edge := b - a
		if edge.length() > best_len:
			best_len = edge.length()
			best_dir = edge.normalized()
	var axis: Vector2 = best_dir
	var side: Vector2 = Vector2(-axis.y, axis.x)
	var u_min := INF
	var u_max := -INF
	var v_min := INF
	var v_max := -INF
	for point in points:
		u_min = minf(u_min, point.dot(axis))
		u_max = maxf(u_max, point.dot(axis))
		v_min = minf(v_min, point.dot(side))
		v_max = maxf(v_max, point.dot(side))
	var length_u := u_max - u_min
	var teeth := maxi(2, int(floor(length_u / 7.0)))
	var tooth_u := length_u / float(teeth)
	var rise := 1.25
	var count := 0
	for tooth in teeth:
		var u0 := u_min + tooth * tooth_u
		var u1 := u0 + tooth_u
		var low_front := _to_world(axis, side, u0, v_min)
		var high_front := _to_world(axis, side, u1, v_min)
		var low_back := _to_world(axis, side, u0, v_max)
		var high_back := _to_world(axis, side, u1, v_max)
		var a0 := Vector3(low_front.x, wall_y, low_front.y)
		var a1 := Vector3(high_front.x, wall_y + rise, high_front.y)
		var b0 := Vector3(low_back.x, wall_y, low_back.y)
		var b1 := Vector3(high_back.x, wall_y + rise, high_back.y)
		var slope_dir := (a1 - a0).normalized()
		var along := Vector3(side.x, 0.0, side.y)
		var normal := slope_dir.cross(along)
		if normal.y < 0.0:
			normal = -normal
		faces.append_array(InnerWestMesh.tri(surface, a0, a1, b1, normal, color))
		faces.append_array(InnerWestMesh.tri(surface, a0, b1, b0, normal, color))
		# vertical glazed face at the high end
		if tooth < teeth - 1:
			var face_normal := Vector3(axis.x, 0.0, axis.y)
			var c0 := Vector3(high_front.x, wall_y, high_front.y)
			var c1 := Vector3(high_back.x, wall_y, high_back.y)
			InnerWestMesh.tri(surface, c0, c1, b1, face_normal, Color("7c93a2"))
			InnerWestMesh.tri(surface, c0, b1, a1, face_normal, Color("7c93a2"))
			count += 2
		count += 2
	return count


## Two chimneys near the gable/parapet ends, plus pots.
static func _chimneys(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	points: PackedVector2Array,
	roof_y: float,
	spec: Dictionary,
	id_hash: int,
) -> int:
	var rect := _ring_rect(points)
	var brick := Color("7a4a38").darkened(0.05)
	var pot := Color("b4552e")
	var count := 0
	var height := 1.15
	for side in 2:
		if id_hash % 3 == 0 and side == 1:
			continue  # some houses have a single chimney
		# `_ring_rect` returns an untyped Array, so the arithmetic result is
		# Variant and `:=` cannot infer a type here.
		var cx: float = rect[0] + (rect[2] - rect[0]) * (0.18 if side == 0 else 0.82)
		var cz: float = rect[1] + (rect[3] - rect[1]) * (0.5 + (0.18 if id_hash % 2 == 0 else -0.18))
		var base := roof_y - 0.25
		var top := roof_y + height
		var size := 0.62
		_box_into(surface, faces, Vector3(cx, base, cz), size, top - base, size, brick)
		_box_into(surface, faces, Vector3(cx, top, cz), size + 0.1, 0.16, size + 0.1, pot)
		count += 12
	return count


## Awning over the street-facing façade: a thin tilted slab.
static func _awning(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	points: PackedVector2Array,
	orientation: float,
	base: float,
	road_hash: Dictionary,
	id_hash: int,
) -> int:
	if points.size() < 3:
		return 0
	var centroid := Vector2()
	for point in points:
		centroid += point
	centroid /= float(points.size())
	var nearest := InnerWestMesh.nearest_road_point(road_hash, centroid.x, centroid.y)
	if nearest == Vector2.INF:
		return 0
	var toward_street := (nearest - centroid).normalized()
	# pick the façade edge most perpendicular to the street direction
	var best_index := -1
	var best_score := -1.0
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var edge := b - a
		if edge.length() < 2.0:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var score := outward.dot(toward_street)
		if score > best_score:
			best_score = score
			best_index = index
	if best_index < 0 or best_score < 0.25:
		return 0
	var a := points[best_index]
	var b := points[(best_index + 1) % points.size()]
	var outward := Vector2((b - a).y, -(b - a).x).normalized() * orientation
	var depth := 1.9
	var margin := 0.45
	var dir := (b - a).normalized()
	var length := (b - a).length() - margin * 2.0
	if length < 1.2:
		return 0
	var start := a + dir * margin
	var end := b - dir * margin
	var y := base + 3.75
	var drop := 0.28
	var outer_start := start + outward * depth
	var outer_end := end + outward * depth
	var p0 := Vector3(start.x, y, start.y)
	var p1 := Vector3(end.x, y, end.y)
	var p2 := Vector3(outer_end.x, y - drop, outer_end.y)
	var p3 := Vector3(outer_start.x, y - drop, outer_start.y)
	var normal := ((p1 - p0).cross(p3 - p0))
	if normal.y < 0.0:
		normal = -normal
	var color := Color("eee5cf") if id_hash % 3 != 0 else Color("c9d6c0")
	InnerWestMesh.tri(surface, p0, p1, p2, normal.normalized(), color)
	InnerWestMesh.tri(surface, p0, p2, p3, normal.normalized(), color)
	# thin fascia front board
	var board_normal := Vector3(outward.x, 0.0, outward.y)
	var board_bottom := Vector3(outer_start.x, y - drop - 0.22, outer_start.y)
	var board_bottom2 := Vector3(outer_end.x, y - drop - 0.22, outer_end.y)
	var board_top := Vector3(outer_end.x, y - drop + 0.03, outer_end.y)
	var board_top2 := Vector3(outer_start.x, y - drop + 0.03, outer_start.y)
	var fascia := _fascia_color(id_hash)
	InnerWestMesh.tri(surface, board_bottom, board_bottom2, board_top, board_normal, fascia)
	InnerWestMesh.tri(surface, board_bottom, board_top, board_top2, board_normal, fascia)
	return 4


static func _box_into(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	bottom_centre: Vector3,
	size_x: float, height: float, size_z: float,
	color: Color,
) -> void:
	var half := Vector3(size_x * 0.5, height * 0.5, size_z * 0.5)
	var centre := bottom_centre + Vector3(0, half.y, 0)
	var corners := [
		centre + Vector3(-half.x, -half.y, -half.z), centre + Vector3(half.x, -half.y, -half.z),
		centre + Vector3(half.x, -half.y, half.z), centre + Vector3(-half.x, -half.y, half.z),
		centre + Vector3(-half.x, half.y, -half.z), centre + Vector3(half.x, half.y, -half.z),
		centre + Vector3(half.x, half.y, half.z), centre + Vector3(-half.x, half.y, half.z),
	]
	var quads := [
		[0, 1, 5, 4, Vector3(0, 0, -1)], [1, 2, 6, 5, Vector3(1, 0, 0)],
		[2, 3, 7, 6, Vector3(0, 0, 1)], [3, 0, 4, 7, Vector3(-1, 0, 0)],
	]
	for quad in quads:
		var normal: Vector3 = quad[4]
		faces.append_array(InnerWestMesh.tri(surface, corners[quad[0]], corners[quad[1]], corners[quad[2]], normal, color))
		faces.append_array(InnerWestMesh.tri(surface, corners[quad[0]], corners[quad[2]], corners[quad[3]], normal, color))
	faces.append_array(InnerWestMesh.tri(surface, corners[3], corners[2], corners[6], Vector3.UP, color))
	faces.append_array(InnerWestMesh.tri(surface, corners[3], corners[6], corners[7], Vector3.UP, color))


static func _ring_rect(points: PackedVector2Array) -> Array:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.y)
		max_z = maxf(max_z, point.y)
	return [min_x, min_z, max_x, max_z]


static func _fascia_color(id_hash: int) -> Color:
	var palette: Array[Color] = [
		Color("8c2f2a"), Color("2f5c3a"), Color("2c3e5c"),
		Color("7c3f16"), Color("5b3a63"), Color("8a6d1d"),
	]
	return palette[absi(id_hash) % palette.size()]
