class_name OperaHouseLandmark
extends Node3D

## Authored Sydney Opera House landmark for the Stage A Sydney world.
##
## Geometry sources (pinned in sydney/landmarks/opera_house.json, derived by
## tests/opera_landmark_data.py from the local OSM extract):
##   relation/9596872  the building outline -> podium / ground footprint (verbatim)
##   relation/9596878  "layer 5 A roof" -> roof plan contours, northern shell row
##   relation/9677509  "layer 4 A roof" -> roof plan contours, southern shell row
##   relation/9677501  "layer 4 c roof" -> Bennelong Restaurant shells
##
## The roof relations are stacked `layer` contours of the same shells, so each
## polygon is one shell's plan, not an independent building. The layer 3
## relations are lower contours of those same shells and are not modelled as
## extra structures.
##
## Heights are authored: the published roof maximum is 67 m above the harbour and
## the shells are sections of a 75 m sphere. Individual apexes are approximations
## fitted to the OSM plan area, not surveyed dimensions.
##
## Winding: like SydneyMesh, this file emits mathematical CCW triangles with
## outward normals and converts once at the Godot boundary through
## SydneyMesh.engine_building_mesh()/engine_building_faces().

const DATA_PATH := "res://sydney/landmarks/opera_house.json"
const PODIUM_TOP := 12.0
const BASE_BAND_TOP := 4.0
const MID_BAND_TOP := 8.0
const SHELL_THICKNESS := 1.05
const S_STEPS := 22
const V_STEPS := 6
const COLLISION_S_STEPS := 6
const COLLISION_V_STEPS := 2
## Stylized landmark emphasis: the roof sails read too small from the bridge
## overlook at the gameplay camera's 600 m viewing distance.
const SHELL_PLAN_SCALE := 1.55
const SHELL_HEIGHT_SCALE := 1.3
const STEP_COUNT := 24
const STEP_RUN := 1.05
const STEP_LOCAL_LIMIT := -38.0
const FORECOURT_DEPTH := 34.0
const GLASS_S := 0.42
## Backward lean of each shell, radians about the lateral axis. The real shells
## lie back over the foyers instead of standing vertical; without this they read
## as domes rather than sails.
const SHELL_TILT := 0.30
const GLASS_STEPS := 8

var data: Dictionary = {}
var build_error := ""
var stats: Dictionary = {}
var podium_ring := PackedVector2Array()
var origin_xz := Vector2.ZERO
var axis_xz := Vector2(0.0, -1.0)
var perp_xz := Vector2(1.0, 0.0)

var _faces := PackedVector3Array()
var _shell_specs: Array = []
var _material_cache: Dictionary = {}


# ------------------------------------------------------------------ loading --
static func read_reference(path: String = DATA_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = parsed
	if String(source.get("format", "")) != "splooge-authored-landmark":
		return {}
	if int(source.get("formatVersion", 0)) != 1:
		return {}
	if not source.has("podiumRing") or not source.has("shells"):
		return {}
	return source


static func ring_from_source(source: Dictionary) -> PackedVector2Array:
	## Cleaned, counter-clockwise podium ring in world XZ. Empty when invalid.
	var raw: Array = source.get("podiumRing", [])
	var points := PackedVector2Array()
	for item in raw:
		if typeof(item) != TYPE_ARRAY or item.size() < 2:
			continue
		var x := float(item[0])
		var z := float(item[1])
		if is_nan(x) or is_inf(x) or is_nan(z) or is_inf(z):
			continue
		var point := Vector2(x, z)
		if points.size() > 0 and points[points.size() - 1].distance_to(point) < 0.001:
			continue
		points.append(point)
	if points.size() > 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
		points.remove_at(points.size() - 1)
	if points.size() < 3:
		return PackedVector2Array()
	if _signed_area(points) < 0.0:
		points.reverse()
	return points


## Drops generic Stage A buildings that would sit inside the landmark footprint.
static func filtered_buildings(rows: Array, podium: PackedVector2Array) -> Array:
	if podium.size() < 3:
		return rows
	var kept: Array = []
	for row in rows:
		var ring: Array = row.get("ring", [])
		if ring.size() > 0:
			var point := Vector2(float(ring[0][0]), float(ring[0][1]))
			if Geometry2D.is_point_in_polygon(point, podium):
				continue
		kept.append(row)
	return kept


## Splits road centre lines that run under the podium, so no ribbon is drawn
## through the building. Unrelated roads are untouched.
static func filtered_roads(rows: Array, podium: PackedVector2Array) -> Array:
	if podium.size() < 3:
		return rows
	var kept: Array = []
	for row in rows:
		var points: Array = row.get("points", [])
		var run: Array = []
		var runs: Array = []
		for point in points:
			var inside := Geometry2D.is_point_in_polygon(
				Vector2(float(point[0]), float(point[1])), podium
			)
			if inside:
				if run.size() >= 2:
					runs.append(run)
				run = []
				continue
			run.append(point)
		if run.size() >= 2:
			runs.append(run)
		for index in runs.size():
			if runs[index].size() == points.size() and index == 0:
				kept.append(row)
				continue
			var copy: Dictionary = row.duplicate(true)
			copy["points"] = runs[index]
			kept.append(copy)
	return kept


# -------------------------------------------------------------------- build --
func build(source: Dictionary = {}) -> bool:
	build_error = ""
	data = source if not source.is_empty() else read_reference()
	if data.is_empty():
		return _fail("landmark reference missing or invalid: " + DATA_PATH)
	podium_ring = ring_from_source(data)
	if podium_ring.size() < 3:
		return _fail("podium ring is invalid")
	if absf(_signed_area(podium_ring)) < 1000.0:
		return _fail("podium footprint is too small: %.1f m2" % absf(_signed_area(podium_ring)))
	var centre: Array = data.get("centreXZ", [0.0, 0.0])
	origin_xz = Vector2(float(centre[0]), float(centre[1]))
	var axis: Array = data.get("axisXZ", [0.0, -1.0])
	axis_xz = Vector2(float(axis[0]), float(axis[1]))
	if axis_xz.length() < 0.5:
		return _fail("podium axis is invalid")
	axis_xz = axis_xz.normalized()
	perp_xz = Vector2(-axis_xz.y, axis_xz.x)
	_shell_specs = data.get("shells", [])
	if _shell_specs.size() < 4:
		return _fail("too few shell plans: %d" % _shell_specs.size())

	var start := Time.get_ticks_usec()
	_faces = PackedVector3Array()
	var counts := {}

	_build_podium()
	counts["podium"] = _mesh_stats(_last_node)
	_build_steps()
	counts["steps"] = _mesh_stats(_last_node)
	_build_forecourt()
	counts["forecourt"] = _mesh_stats(_last_node)
	_build_shells()
	counts["shells"] = _mesh_stats(_last_node)
	_build_glazing()
	counts["glazing"] = _mesh_stats(_last_node)
	_build_shell_collision()
	_build_collision()

	stats = {
		"shells": _shell_specs.size(),
		"podiumAreaM2": snappedf(absf(_signed_area(podium_ring)), 0.1),
		"vertices": _total(counts, "vertices"),
		"triangles": _total(counts, "triangles"),
		"collisionTriangles": _faces.size() / 3,
		"parts": counts,
		"buildMs": (Time.get_ticks_usec() - start) / 1000.0,
	}
	return true


func _fail(message: String) -> bool:
	build_error = message
	push_error("OperaHouseLandmark: " + message)
	return false


var _last_node: MeshInstance3D


func _total(counts: Dictionary, key: String) -> int:
	var sum := 0
	for name in counts:
		sum += int(counts[name].get(key, 0))
	return sum


func _mesh_stats(node: Node) -> Dictionary:
	if node == null or not (node is MeshInstance3D):
		return {"vertices": 0, "triangles": 0}
	var mesh: ArrayMesh = (node as MeshInstance3D).mesh
	var vertices := 0
	var triangles := 0
	for index in mesh.get_surface_count():
		vertices += mesh.surface_get_array_len(index)
		var arrays := mesh.surface_get_arrays(index)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and indices.size() > 0:
			triangles += indices.size() / 3
		else:
			triangles += mesh.surface_get_array_len(index) / 3
	return {"vertices": vertices, "triangles": triangles}


# ------------------------------------------------------------------ surfaces --
func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


func _commit(surface: SurfaceTool, node_name: String, material: Material) -> MeshInstance3D:
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		_last_node = null
		return null
	# Mathematical CCW -> Godot clockwise front faces, once, at the boundary.
	var converted := SydneyMesh.engine_building_mesh(mesh)
	converted.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = converted
	add_child(instance)
	_last_node = instance
	return instance


func _tri(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	reference: Vector3,
	collide: bool = true,
) -> void:
	_tri_n(surface, a, normal, b, normal, c, normal, reference, collide)


func _tri_n(
	surface: SurfaceTool,
	a: Vector3,
	na: Vector3,
	b: Vector3,
	nb: Vector3,
	c: Vector3,
	nc: Vector3,
	reference: Vector3,
	collide: bool = true,
) -> void:
	var face := (b - a).cross(c - a)
	if face.length() < 0.000001:
		return
	if face.dot(reference) < 0.0:
		var swap_point := b
		var swap_normal := nb
		b = c
		nb = nc
		c = swap_point
		nc = swap_normal
	surface.set_normal(na)
	surface.add_vertex(a)
	surface.set_normal(nb)
	surface.add_vertex(b)
	surface.set_normal(nc)
	surface.add_vertex(c)
	if collide:
		_faces.append_array([a, b, c])


func _flat(surface: SurfaceTool, ring: PackedVector2Array, y: float, collide := false) -> void:
	if ring.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(ring)
	if indices.is_empty():
		return
	for index in range(0, indices.size(), 3):
		var a := ring[indices[index]]
		var b := ring[indices[index + 1]]
		var c := ring[indices[index + 2]]
		_tri(
			surface,
			Vector3(a.x, y, a.y),
			Vector3(b.x, y, b.y),
			Vector3(c.x, y, c.y),
			Vector3.UP,
			Vector3.UP,
			collide,
		)


func _extrude(surface: SurfaceTool, ring: PackedVector2Array, y0: float, y1: float, collide := true) -> void:
	if ring.size() < 3 or y1 - y0 < 0.01:
		return
	var area := _signed_area(ring)
	if absf(area) < 0.5:
		return
	var orientation := 1.0 if area > 0.0 else -1.0
	for index in ring.size():
		var a := ring[index]
		var b := ring[(index + 1) % ring.size()]
		var edge := b - a
		if edge.length() < 0.001:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var normal := Vector3(outward.x, 0.0, outward.y)
		var p0 := Vector3(a.x, y0, a.y)
		var p1 := Vector3(b.x, y0, b.y)
		var p2 := Vector3(b.x, y1, b.y)
		var p3 := Vector3(a.x, y1, a.y)
		_tri(surface, p0, p1, p2, normal, normal, collide)
		_tri(surface, p0, p2, p3, normal, normal, collide)
	_flat(surface, ring, y1, collide)


# -------------------------------------------------------------------- podium --
func _build_podium() -> void:
	var surface := _surface()
	var tiers := [
		[0.0, BASE_BAND_TOP, 0.8],           # plinth, slightly proud of the outline
		[BASE_BAND_TOP, MID_BAND_TOP, -1.7],
		[MID_BAND_TOP, PODIUM_TOP, -3.3],
	]
	for tier in tiers:
		var ring := _buffer_ring(podium_ring, float(tier[2]))
		if ring.size() < 3:
			continue
		_extrude(surface, ring, float(tier[0]), float(tier[1]))
	_commit(surface, "OperaPodium", _material("stone", Color("cdbca1"), 0.95, 0.0))
	_build_deck()


func _build_deck() -> void:
	var surface := _surface()
	var ring := _buffer_ring(podium_ring, -3.3)
	_flat(surface, ring, PODIUM_TOP + 0.02, true)
	_commit(surface, "OperaDeck", _material("deck", Color("d9ceb6"), 0.92, 0.0))


## Broad monumental steps at the southern end. Each step is a solid tier, so the
## silhouette reads as the real stepped base and the tiers collide as solid rock.
func _build_steps() -> void:
	var surface := _surface()
	var limit := STEP_LOCAL_LIMIT + origin_xz.dot(axis_xz)
	for index in STEP_COUNT:
		var expanded := _buffer_ring(podium_ring, float(index + 1) * STEP_RUN)
		var clipped := _clip_halfplane(expanded, axis_xz, limit)
		if clipped.size() < 3:
			continue
		var top := PODIUM_TOP - float(index + 1) * (PODIUM_TOP / float(STEP_COUNT))
		if top < 0.05:
			continue
		_extrude(surface, clipped, 0.0, top)
	_commit(surface, "OperaSteps", _material("stone", Color("cdbca1"), 0.95, 0.0))


func _build_forecourt() -> void:
	var surface := _surface()
	var plaza := _buffer_ring(podium_ring, FORECOURT_DEPTH)
	plaza = _clip_halfplane(plaza, axis_xz, STEP_LOCAL_LIMIT + 14.0 + origin_xz.dot(axis_xz))
	_flat(surface, plaza, 0.12)
	_commit(surface, "OperaForecourt", _material("paving", Color("c3b8a1"), 0.96, 0.0))


# -------------------------------------------------------------------- shells --
func _build_shells() -> void:
	var surface := _surface()
	for spec in _shell_specs:
		_add_shell(surface, spec, S_STEPS, V_STEPS, true, true)
	_commit(surface, "OperaShells", _material("shell", Color("f4f1e4"), 0.33, 0.04))


func _build_shell_collision() -> void:
	# Coarse tessellation: the shells only need collision where a player could
	# reach them from the podium deck, so no full-resolution duplicate is kept.
	var surface := _surface()
	for spec in _shell_specs:
		_add_shell(surface, spec, COLLISION_S_STEPS, COLLISION_V_STEPS, false, true)
	var discarded := surface.commit()
	if discarded != null:
		discarded = null


func _add_shell(
	surface: SurfaceTool,
	spec: Dictionary,
	s_steps: int,
	v_steps: int,
	with_inner: bool,
	collide: bool,
) -> void:
	var obb: Dictionary = spec.get("obb", {})
	var ring: Array = spec.get("ring", [])
	if obb.is_empty() or ring.size() < 3:
		return
	var centre: Array = obb.get("centre", [0.0, 0.0])
	var axis: Array = obb.get("axis", [0.0, -1.0])
	var c := Vector2(float(centre[0]), float(centre[1]))
	var ax := Vector2(float(axis[0]), float(axis[1]))
	if ax.length() < 0.5:
		return
	ax = ax.normalized()
	var length := float(obb.get("lengthM", 20.0)) * SHELL_PLAN_SCALE
	var width := float(obb.get("widthM", 12.0)) * SHELL_PLAN_SCALE
	if length < 2.0 or width < 2.0:
		return
	var height := maxf(float(spec.get("apexAboveGroundM", 55.0)) - PODIUM_TOP, 4.0) * SHELL_HEIGHT_SCALE
	var group := String(spec.get("group", ""))
	var lean := 0.0
	if group == "concert-hall":
		lean = -0.16 * width
	elif group == "opera-theatre":
		lean = 0.16 * width
	var vax := Vector2(-ax.y, ax.x)
	for side in [-1.0, 1.0]:
		_add_shell_half(surface, c, ax, vax, length, width, height, lean, float(side), s_steps, v_steps, with_inner, collide)


func _add_shell_half(
	surface: SurfaceTool,
	c: Vector2,
	ax: Vector2,
	vax: Vector2,
	length: float,
	width: float,
	height: float,
	lean: float,
	side: float,
	s_steps: int,
	v_steps: int,
	with_inner: bool,
	collide: bool,
) -> void:
	var rows: Array = []
	var inner_rows: Array = []
	for i in s_steps + 1:
		var s := -1.0 + 2.0 * float(i) / float(s_steps)
		var row: Array = []
		var inner_row: Array = []
		for j in v_steps + 1:
			var v := float(j) / float(v_steps) * side
			var point := _shell_vertex(c, ax, vax, length, width, height, lean, s, v)
			var normal := _shell_normal(c, ax, vax, length, width, height, lean, s, v, side)
			row.append([point, normal])
			if with_inner:
				# The ridge is a crease; both halves must offset from the same
				# bisector or the inner surfaces would leave a slit.
				var offset_normal := normal if absf(v) > 1e-9 else Vector3.UP
				inner_row.append([point - offset_normal * SHELL_THICKNESS, -normal])
		rows.append(row)
		if with_inner:
			inner_rows.append(inner_row)

	for i in s_steps:
		for j in v_steps:
			var a: Array = rows[i][j]
			var b: Array = rows[i][j + 1]
			var d: Array = rows[i + 1][j]
			var e: Array = rows[i + 1][j + 1]
			_tri_n(surface, a[0], a[1], b[0], b[1], e[0], e[1], (a[1] + b[1] + e[1]).normalized(), collide)
			_tri_n(surface, a[0], a[1], e[0], e[1], d[0], d[1], (a[1] + e[1] + d[1]).normalized(), collide)
			if with_inner:
				var ia: Array = inner_rows[i][j]
				var ib: Array = inner_rows[i][j + 1]
				var id: Array = inner_rows[i + 1][j]
				var ie: Array = inner_rows[i + 1][j + 1]
				_tri_n(surface, ia[0], ia[1], ib[0], ib[1], ie[0], ie[1], (ia[1] + ib[1] + ie[1]).normalized(), collide)
				_tri_n(surface, ia[0], ia[1], ie[0], ie[1], id[0], id[1], (ia[1] + ie[1] + id[1]).normalized(), collide)

	if not with_inner:
		return

	# Rim along the free lateral edge (v = side).
	var last := v_steps
	for i in s_steps:
		_rim_quad(
			surface,
			rows[i][last][0], rows[i + 1][last][0],
			inner_rows[i + 1][last][0], inner_rows[i][last][0],
			collide,
		)
	# End rims at s = -1 and s = +1.
	for j in v_steps:
		_rim_quad(
			surface,
			rows[0][j][0], rows[0][j + 1][0],
			inner_rows[0][j + 1][0], inner_rows[0][j][0],
			collide,
		)
		_rim_quad(
			surface,
			rows[s_steps][j][0], rows[s_steps][j + 1][0],
			inner_rows[s_steps][j + 1][0], inner_rows[s_steps][j][0],
			collide,
		)


func _rim_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, collide: bool) -> void:
	var outward := ((a + b) * 0.5 - (c + d) * 0.5)
	if outward.length() < 0.0001:
		return
	outward = outward.normalized()
	_tri(surface, a, b, c, outward, outward, collide)
	_tri(surface, a, c, d, outward, outward, collide)


func _shell_width(s: float, width: float) -> float:
	## Half-width of the lens plan. The floor keeps the tips from collapsing into
	## degenerate triangles at a 40 m scale.
	return maxf(width * 0.5 * sqrt(maxf(1.0 - s * s, 0.0)), 0.5)


func _shell_height(s: float, height: float) -> float:
	## Sail profile. s = -1 is the high south face, s = +1 the harbour tip.
	## The apex sits about a third of the way back from the south end: the shell
	## rises steeply off the glass foyer and sweeps down to a long northern point.
	var t := clampf((s + 1.0) * 0.5, 0.0, 1.0)
	return height * sin(PI * pow(t, 0.74))


func _shell_profile(v: float) -> float:
	## Pointed cross-section: a crisp ridge crease at v = 0 falling to the rim.
	return 1.0 - pow(absf(v), 1.6)


func _shell_vertex(
	c: Vector2,
	ax: Vector2,
	vax: Vector2,
	length: float,
	width: float,
	height: float,
	lean: float,
	s: float,
	v: float,
) -> Vector3:
	var half_width := _shell_width(s, width)
	var rise := _shell_height(s, height) * _shell_profile(v)
	var lateral := v * half_width + lean * (rise / height)
	var along := s * length * 0.5
	# Lay the shell back over the harbour: the apex shifts toward the north tip and
	# drops, which is what turns a dome into a sail.
	var cos_tilt := cos(SHELL_TILT)
	var sin_tilt := sin(SHELL_TILT)
	var tilted_along := along * cos_tilt + rise * sin_tilt
	var tilted_rise := maxf(0.0, rise * cos_tilt - along * sin_tilt)
	var planar := c + ax * tilted_along + vax * lateral
	return Vector3(planar.x, PODIUM_TOP + tilted_rise, planar.y)


func _shell_normal(
	c: Vector2,
	ax: Vector2,
	vax: Vector2,
	length: float,
	width: float,
	height: float,
	lean: float,
	s: float,
	v: float,
	side: float,
) -> Vector3:
	var step := 0.004
	var s0 := s
	var s1 := s
	if s >= 1.0 - 1e-9:
		s0 = s - step
	elif s <= -1.0 + 1e-9:
		s1 = s + step
	else:
		s0 = s - step
		s1 = s + step
	var v0 := v
	var v1 := v
	if absf(v) < 1e-9:
		v1 = side * 0.01
	else:
		v0 = v - side * 0.01
		v1 = v + side * 0.01
	var p0 := _shell_vertex(c, ax, vax, length, width, height, lean, s0, v)
	var p1 := _shell_vertex(c, ax, vax, length, width, height, lean, s1, v)
	var q0 := _shell_vertex(c, ax, vax, length, width, height, lean, s, v0)
	var q1 := _shell_vertex(c, ax, vax, length, width, height, lean, s, v1)
	var along_s := (p1 - p0)
	var along_v := (q1 - q0)
	if along_s.length() < 1e-6 or along_v.length() < 1e-6:
		return Vector3.UP
	var normal := along_v.normalized().cross(along_s.normalized())
	if normal.length() < 1e-6:
		return Vector3.UP
	normal = normal.normalized()
	if normal.y < 0.0:
		normal = -normal
	return normal


# ------------------------------------------------------------------- glazing --
func _build_glazing() -> void:
	var surface := _surface()
	for spec in _shell_specs:
		_add_shell_glass(surface, spec)
	_commit(surface, "OperaGlazing", _material("glass", Color("23343e"), 0.14, 0.5, true))


## Foyer glazing: a vertical curtain under the northern (harbour) end of each
## shell, closed by the shell's own underside.
func _add_shell_glass(surface: SurfaceTool, spec: Dictionary) -> void:
	var obb: Dictionary = spec.get("obb", {})
	if obb.is_empty():
		return
	var centre: Array = obb.get("centre", [0.0, 0.0])
	var axis: Array = obb.get("axis", [0.0, -1.0])
	var c := Vector2(float(centre[0]), float(centre[1]))
	var ax := Vector2(float(axis[0]), float(axis[1]))
	if ax.length() < 0.5:
		return
	ax = ax.normalized()
	var length := float(obb.get("lengthM", 20.0))
	var width := float(obb.get("widthM", 12.0))
	if length < 6.0:
		return
	var height := maxf(float(spec.get("apexAboveGroundM", 55.0)) - PODIUM_TOP, 4.0)
	var group := String(spec.get("group", ""))
	var lean := 0.0
	if group == "concert-hall":
		lean = -0.16 * width
	elif group == "opera-theatre":
		lean = 0.16 * width
	var vax := Vector2(-ax.y, ax.x)
	var tops: Array = []
	var bottoms: Array = []
	for j in GLASS_STEPS + 1:
		var v := -0.9 + 1.8 * float(j) / float(GLASS_STEPS)
		var top := _shell_vertex(c, ax, vax, length, width, height, lean, GLASS_S, v)
		var normal := _shell_normal(c, ax, vax, length, width, height, lean, GLASS_S, v, 1.0)
		var underside := top - normal * SHELL_THICKNESS
		if underside.y <= PODIUM_TOP + 0.2:
			continue
		tops.append(underside)
		bottoms.append(Vector3(underside.x, PODIUM_TOP + 0.05, underside.z))
	for index in tops.size() - 1:
		var a: Vector3 = bottoms[index]
		var b: Vector3 = bottoms[index + 1]
		var ctop: Vector3 = tops[index + 1]
		var dtop: Vector3 = tops[index]
		var reference := Vector3(ax.x, 0.0, ax.y)
		_tri(surface, a, b, ctop, reference, reference, false)
		_tri(surface, a, ctop, dtop, reference, reference, false)


# ----------------------------------------------------------------- materials --
func _material(key: String, color: Color, roughness: float, metallic: float, mirror := false) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if mirror else BaseMaterial3D.CULL_BACK
	_material_cache[key] = material
	return material


# ------------------------------------------------------------------ geometry --
static func _signed_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## Bounded mitre buffer: positive grows the ring, negative shrinks it.
##
## This replaces Geometry2D.offset_polygon, which on this outline can return an
## unbounded artefact for a large delta; that silently became a terrain-sized
## apron instead of the podium detail. A clamped mitre cannot exceed three times
## the requested distance, so an offset can never run away.
func _buffer_ring(ring: PackedVector2Array, distance: float) -> PackedVector2Array:
	if ring.size() < 3 or absf(distance) < 0.0001:
		return ring
	var orientation := 1.0 if _signed_area(ring) >= 0.0 else -1.0
	var out := PackedVector2Array()
	for index in ring.size():
		var previous := ring[(index - 1 + ring.size()) % ring.size()]
		var current := ring[index]
		var following := ring[(index + 1) % ring.size()]
		var incoming := current - previous
		var outgoing := following - current
		if incoming.length() < 0.000001 or outgoing.length() < 0.000001:
			continue
		incoming = incoming.normalized()
		outgoing = outgoing.normalized()
		var first_normal := Vector2(incoming.y, -incoming.x) * orientation
		var second_normal := Vector2(outgoing.y, -outgoing.x) * orientation
		var bisector := first_normal + second_normal
		if bisector.length() < 0.000001:
			out.append(current + first_normal * distance)
			continue
		bisector = bisector.normalized()
		var dot := maxf(bisector.dot(first_normal), 0.35)
		var reach := minf(distance / dot, absf(distance) * 3.0)
		out.append(current + bisector * reach)
	if out.size() < 3:
		return ring
	return out


func _clip_halfplane(points: PackedVector2Array, normal: Vector2, offset: float) -> PackedVector2Array:
	if points.size() < 3:
		return PackedVector2Array()
	var out := PackedVector2Array()
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var da := a.dot(normal) - offset
		var db := b.dot(normal) - offset
		var a_in := da <= 0.0
		var b_in := db <= 0.0
		if a_in:
			out.append(a)
		if a_in != b_in:
			var denominator := da - db
			if absf(denominator) < 1e-9:
				continue
			out.append(a.lerp(b, da / denominator))
	return out


# ----------------------------------------------------------------- collision --
func _build_collision() -> void:
	if _faces.size() < 3:
		return
	var body := StaticBody3D.new()
	body.name = "OperaCollision"
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(SydneyMesh.engine_building_faces(_faces))
	collider.shape = shape
	body.add_child(collider)
