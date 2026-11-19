extends RefCounted

## District-aware facade builder for the expanded Sydney CBD (Phase 6B).
##
## The base importer (`SydneyMesh.buildings`) extrudes a flat vertex-coloured
## shell: correct, collision-parity safe, and deliberately plain. This builder is
## the Phase 6B architecture pass. It keeps the *exact* exported footprint (and
## therefore the geographic shell and its collision) but gives each building:
##
##   * a facade family taken from the district export (glass tower, pale stone,
##     brick commercial, retail podium, terrace, sandstone, warehouse, apartment);
##   * horizontal floor banding so height reads at street level;
##   * a cornice / parapet cap, and a podium-plus-tower mass for tall towers;
##   * corner pilasters and rooftop plant on the families that carry them;
##   * deterministic per-building colour and band variation, so a terrace row is
##     a row of related buildings rather than one mesh repeated.
##
## Convention: geometry is emitted mathematically counter-clockwise about its
## outward normal, exactly like `SydneyMesh.buildings()`. `CbdWorld` converts it
## once at the engine boundary with `SydneyMesh.engine_building_mesh()` and
## `engine_building_faces()`, so rendered and collision triangles stay identical
## and the engine-front-face winding is the same as every other Sydney surface.
##
## Nothing here is surveyed detail: bands, cornices, parapets and podiums are
## authored presentation. The footprint, position and height are the data.

const MeshBuilder := preload("res://sydney/sydney_mesh.gd")

const MAX_BANDS := 12
const STOREY := 3.4
## Low-rise masonry families get a pitched roof. This is the single strongest
## district cue: Surry Hills, Darlinghurst and The Rocks are rows of roofs, not
## rows of flat lids.
const PITCHED_STYLES := ["terrace", "sandstone", "warehouse"]
const PITCHED_MAX_HEIGHT := 24.0
const WINDOW_FLOOR_HEIGHT := 3.4
const WINDOW_EMISSION_COLORS := [
	Color("ffc982"),
	Color("dce9ff"),
	Color("8ac9ff"),
]
const WINDOW_EMISSION_LEVELS := [3.2, 2.4, 2.0]

# Authored facade families. `wall` is the spandrel/pier colour, `glass` the
# window band, `podium` the ground floor, `trim` the parapet, `roof` the top.
const FAMILIES := {
	"glass-tower": {
		"wall": Color("5a6a70"), "glass": Color("22343d"), "podium": Color("9b907c"),
		"trim": Color("93a0a3"), "roof": Color("626b6f"), "podium_height": 18.0,
		"cornice": false, "piers": true, "plant": true,
	},
	"stone-commercial": {
		"wall": Color("b6aa93"), "glass": Color("33434a"), "podium": Color("948873"),
		"trim": Color("cfc4ac"), "roof": Color("777264"), "podium_height": 9.0,
		"cornice": true, "piers": true, "plant": false,
	},
	"brick-commercial": {
		"wall": Color("85533f"), "glass": Color("2c383c"), "podium": Color("724734"),
		"trim": Color("b5a687"), "roof": Color("5c4438"), "podium_height": 5.0,
		"cornice": true, "piers": true, "plant": false,
	},
	"retail": {
		"wall": Color("a79982"), "glass": Color("2d444c"), "podium": Color("756451"),
		"trim": Color("c9bb9f"), "roof": Color("74736a"), "podium_height": 4.6,
		"cornice": true, "piers": false, "plant": false,
	},
	"terrace": {
		"wall": Color("a89a85"), "glass": Color("33454b"), "podium": Color("938571"),
		"trim": Color("c7b99e"), "roof": Color("66625a"), "podium_height": 0.0,
		"cornice": true, "piers": true, "plant": false,
	},
	"sandstone": {
		"wall": Color("bda67f"), "glass": Color("38494e"), "podium": Color("a98e68"),
		"trim": Color("d2bd97"), "roof": Color("8b7860"), "podium_height": 0.0,
		"cornice": true, "piers": true, "plant": false,
	},
	"warehouse": {
		"wall": Color("8d604b"), "glass": Color("303c40"), "podium": Color("774e3a"),
		"trim": Color("b4a488"), "roof": Color("57463b"), "podium_height": 0.0,
		"cornice": true, "piers": false, "plant": false,
	},
	"apartment": {
		"wall": Color("aca392"), "glass": Color("3a525c"), "podium": Color("968d7c"),
		"trim": Color("cbc2ad"), "roof": Color("6f6f68"), "podium_height": 4.0,
		"cornice": true, "piers": false, "plant": true,
	},
}

var stats: Dictionary = {}


func build(rows: Array, _spawn: Vector3) -> Dictionary:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var window_surfaces: Array[SurfaceTool] = []
	for _color_index in WINDOW_EMISSION_COLORS.size():
		var window_surface := SurfaceTool.new()
		window_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		window_surfaces.append(window_surface)
	var faces := PackedVector3Array()
	var built := 0
	var skipped := 0
	var degenerate := 0
	var triangles := 0
	var night_window_quads := 0
	var by_style: Dictionary = {}
	var detached := 0

	for row in rows:
		var ring := MeshBuilder._clean_ring(row.get("ring", []))
		if ring.size() < 3:
			skipped += 1
			continue
		var height := clampf(float(row.get("heightM", 8.0)), 3.0, 240.0)
		if absf(MeshBuilder._signed_area(ring)) < 1.0:
			skipped += 1
			continue
		if Geometry2D.triangulate_polygon(ring).is_empty():
			skipped += 1
			continue
		var style := str(row.get("style", "stone-commercial"))
		var family: Dictionary = FAMILIES.get(style, FAMILIES["stone-commercial"])
		var identity := str(row.get("id", ""))
		var variant := absi(identity.hash())

		var emitted := _emit_building(surface, faces, ring, height, style, family, variant)
		if emitted.get("triangles", 0) <= 0:
			skipped += 1
			continue
		degenerate += int(emitted.get("degenerate", 0))
		triangles += int(emitted.get("triangles", 0))
		# Night-window quads are superseded by the aligned procedural windows in
		# facade.gdshader, and the resulting mesh was always hidden at runtime.
		# Generating 423k invisible quads cost ~1 s of startup and ~850k
		# triangles of memory for no visible result, so it is skipped.
		built += 1
		if bool(emitted.get("detached", false)):
			detached += 1
		by_style[style] = int(by_style.get(style, 0)) + 1

	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		# Without this the city renders in the default white material: the
		# per-vertex facade colours only show with the project's shared
		# vertex-colour material, exactly as SydneyMesh.buildings() does it.
		mesh.surface_set_material(0, MeshBuilder.vertex_mat())
	var window_mesh := _commit_night_windows(window_surfaces)
	stats = {
		"built": built,
		"skipped": skipped,
		"degenerateTriangles": degenerate,
		"triangles": triangles,
		"collisionTriangles": faces.size() / 3,
		"detachedPodiums": detached,
		"byStyle": by_style,
		"nightWindowQuads": night_window_quads,
	}
	return {
		"mesh": mesh,
		"faces": faces,
		"nightWindows": window_mesh,
		"stats": stats,
	}


func _emit_night_windows(
	surfaces: Array[SurfaceTool],
	ring: PackedVector2Array,
	height: float,
	style: String,
	identity: String,
) -> int:
	if height < 3.0 or ring.size() < 3:
		return 0

	var base_chance := 0.2
	match style:
		"glass-tower", "apartment":
			base_chance = 0.34
		"stone-commercial", "brick-commercial", "retail":
			base_chance = 0.28
		"terrace", "sandstone":
			base_chance = 0.19
		"warehouse":
			base_chance = 0.1

	var rng := RandomNumberGenerator.new()
	rng.seed = absi(identity.hash()) + 1
	var orientation := signf(MeshBuilder._signed_area(ring))
	var floor_count := clampi(int(floor(height / WINDOW_FLOOR_HEIGHT)), 1, 24)
	var quads := 0

	for edge_index in ring.size():
		var start := ring[edge_index]
		var finish := ring[(edge_index + 1) % ring.size()]
		var edge := finish - start
		var edge_length := edge.length()
		if edge_length < 2.4:
			continue
		var window_count := clampi(int(edge_length / 3.2), 1, 32)
		var spacing := edge_length / float(window_count)
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var normal := Vector3(outward.x, 0.0, outward.y)
		var inset := edge.normalized()

		for floor_index in floor_count:
			var floor_bottom := float(floor_index) * WINDOW_FLOOR_HEIGHT
			if floor_bottom + 1.0 >= height:
				continue
			var ground_floor := floor_index == 0
			var chance := 0.62 if ground_floor and style in [
				"glass-tower", "stone-commercial", "brick-commercial", "retail"
			] else base_chance
			var window_height := 1.1 if ground_floor else 1.45
			var bottom_y := floor_bottom + (0.55 if ground_floor else 1.0)
			if bottom_y + window_height > height - 0.2:
				continue

			for slot in window_count:
				if rng.randf() > chance:
					continue
				var center := start + inset * (spacing * (float(slot) + 0.5))
				var width := minf(1.25 if ground_floor else 1.05, spacing * 0.54)
				if width < 0.32:
					continue
				var a := Vector3(center.x, bottom_y, center.y) + Vector3(outward.x, 0.0, outward.y) * 0.045
				var b := a + Vector3(inset.x, 0.0, inset.y) * width
				var c := b + Vector3.UP * window_height
				var d := a + Vector3.UP * window_height
				var color_index := _window_color_index(rng)
				_add_window_quad(surfaces[color_index], a, b, c, d, normal)
				quads += 1
	return quads


func _window_color_index(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < 0.14:
		return 2
	if roll < 0.48:
		return 1
	return 0


func _add_window_quad(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	normal: Vector3,
) -> void:
	for point in [a, b, c, a, c, d]:
		surface.set_normal(normal)
		surface.add_vertex(point)


func _commit_night_windows(surfaces: Array[SurfaceTool]) -> ArrayMesh:
	var result := ArrayMesh.new()
	for color_index in surfaces.size():
		var mesh := surfaces[color_index].commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		if arrays[Mesh.ARRAY_VERTEX].is_empty():
			continue
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_color = WINDOW_EMISSION_COLORS[color_index].darkened(0.72)
		material.emission_enabled = true
		material.emission = WINDOW_EMISSION_COLORS[color_index]
		material.emission_energy_multiplier = 0.0
		material.set_meta("night_energy", WINDOW_EMISSION_LEVELS[color_index])
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		result.surface_set_material(result.get_surface_count() - 1, material)
	return result


func _emit_building(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	ring: PackedVector2Array,
	height: float,
	style: String,
	family: Dictionary,
	variant: int,
) -> Dictionary:
	var pod_height := float(family.get("podium_height", 0.0))
	var podium := pod_height > 0.0 and height > pod_height + 10.0
	var tower_ring := ring
	var tower_height := height
	var detached := false

	if podium:
		# A tall tower over a lower street wall. The inset is authored but small
		# (2.2-3.4 m) so it stays inside the exported parcel and never overlaps
		# the neighbouring building.
		var inset := 2.2 + float(variant % 13) * 0.09
		var candidate := _inset_ring(ring, inset)
		if candidate.size() >= 3 \
			and absf(MeshBuilder._signed_area(candidate)) > absf(MeshBuilder._signed_area(ring)) * 0.34 \
			and not Geometry2D.triangulate_polygon(candidate).is_empty():
			tower_ring = candidate
			detached = true
		else:
			podium = false

	var total := 0
	var degenerate := 0
	if podium:
		var lower := _emit_mass(surface, faces, ring, 0.0, pod_height, style, family, variant, 3, true, false)
		total += int(lower["triangles"])
		degenerate += int(lower.get("degenerate", 0))
		# A slab at the podium top so the setback reads as a real ledge.
		total += _emit_roof(surface, faces, ring, pod_height, family)
	# The shaft: bands climb the whole height, so floors read at street level.
	var bands := clampi(int(round(height / STOREY)), 1, MAX_BANDS)
	var shaft := _emit_mass(
		surface, faces, tower_ring, pod_height if podium else 0.0, tower_height,
		style, family, variant, bands, true, not podium)
	total += int(shaft["triangles"])
	degenerate += int(shaft.get("degenerate", 0))
	var pitched := (not podium) and style in PITCHED_STYLES and height <= PITCHED_MAX_HEIGHT \
		and tower_ring.size() <= 6 and _is_convex(tower_ring)
	if pitched:
		total += _emit_pitched_roof(surface, faces, tower_ring, tower_height, family, variant)
	else:
		total += _emit_roof(surface, faces, tower_ring, tower_height, family)

	if bool(family.get("plant", false)) or (style == "stone-commercial" and height > 60.0):
		total += _emit_plant(surface, faces, tower_ring, tower_height, family, variant)

	return {
		"triangles": total,
		"degenerate": degenerate,
		"detached": detached,
	}


## One vertical mass: banded wall quads per footprint edge, an optional cornice
## and optional corner pilasters, plus a parapet cap.
func _emit_mass(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	ring: PackedVector2Array,
	y0: float,
	y1: float,
	style: String,
	family: Dictionary,
	variant: int,
	band_count: int,
	cap: bool,
	is_ground: bool,
) -> Dictionary:
	var total := 0
	var degenerate := 0
	var span := maxf(y1 - y0, 0.1)
	if ring.size() < 3:
		return {"triangles": 0, "degenerate": 0}
	var orientation := signf(MeshBuilder._signed_area(ring))
	var bands := maxi(band_count, 1)
	# Authored per-building tint so a row of terraces is not one colour repeated.
	var tint := (float(variant % 17) - 8.0) / 100.0
	var wall: Color = _tint(family["wall"], tint)
	var glass: Color = _tint(family["glass"], tint * 0.5)
	var podium: Color = _tint(family["podium"], tint)
	var trim: Color = family["trim"]

	for index in ring.size():
		var a := ring[index]
		var b := ring[(index + 1) % ring.size()]
		var edge := b - a
		if edge.length() < 0.05:
			continue
		var outward := Vector2(edge.y, -edge.x).normalized() * orientation
		var normal := Vector3(outward.x, 0.0, outward.y)

		for band in bands:
			var low := y0 + span * float(band) / float(bands)
			var high := y0 + span * float(band + 1) / float(bands)
			var color := wall
			if is_ground and band == 0 and y0 <= 0.001:
				color = podium
			elif band == bands - 1:
				color = trim
			elif style == "glass-tower":
				# Curtain wall: mostly glass with occasional mullion floors.
				color = wall if band % 4 == 0 else glass
			else:
				# Masonry stays masonry. The old full-glass bands printed stripes
				# across every facade; window detail now comes from the shader.
				color = wall.darkened(0.055) if band % 2 == 1 else wall
			# Alpha tags the facade family for the shader (0.2 = curtain wall).
			color.a = 0.2 if style == "glass-tower" else 1.0
			var p0 := Vector3(a.x, low, a.y)
			var p1 := Vector3(b.x, low, b.y)
			var p2 := Vector3(b.x, high, b.y)
			var p3 := Vector3(a.x, high, a.y)
			var added := _quad(surface, faces, p0, p1, p2, p3, normal, color)
			total += added["triangles"]
			degenerate += int(added["degenerate"])

		# Corner pilaster: a narrow vertical face at each footprint vertex. Two
		# triangles per corner, and it is what stops a long facade reading as a
		# printed stripe.
		if bool(family["piers"]) and span > 3.0:
			var previous := ring[(index + ring.size() - 1) % ring.size()]
			var next := ring[(index + 2) % ring.size()]
			var inner_a := (previous - a)
			var inner_b := (next - b)
			if inner_a.length() > 1.2 and inner_b.length() > 1.2:
				var pa := a + (inner_a.normalized() * minf(0.55, inner_a.length() * 0.4))
				var pb := b + (inner_b.normalized() * minf(0.55, inner_b.length() * 0.4))
				var pier_normal := Vector3(outward.x, 0.0, outward.y)
				var proud := 0.12
				var l0 := Vector3(pa.x + outward.x * proud, y0, pa.y + outward.y * proud)
				var l1 := Vector3(pb.x + outward.x * proud, y0, pb.y + outward.y * proud)
				var l2 := Vector3(pb.x + outward.x * proud, y1, pb.y + outward.y * proud)
				var l3 := Vector3(pa.x + outward.x * proud, y1, pa.y + outward.y * proud)
				var added := _quad(surface, faces, l0, l1, l2, l3, pier_normal, wall.darkened(0.06))
				total += added["triangles"]
				degenerate += int(added["degenerate"])

		# Cornice lip along the top edge: a horizontal shelf, so the roofline has
		# a shadow line instead of a knife edge.
		if cap and bool(family["cornice"]):
			var lip := 0.28
			var c0 := Vector3(a.x, y1, a.y)
			var c1 := Vector3(b.x, y1, b.y)
			var c2 := Vector3(b.x + outward.x * lip, y1, b.y + outward.y * lip)
			var c3 := Vector3(a.x + outward.x * lip, y1, a.y + outward.y * lip)
			var added := _quad(surface, faces, c0, c1, c2, c3, Vector3(outward.x, 0.55, outward.y).normalized(), trim)
			total += added["triangles"]
			degenerate += int(added["degenerate"])

	return {"triangles": total, "degenerate": degenerate}


func _emit_roof(surface: SurfaceTool, faces: PackedVector3Array, ring: PackedVector2Array, y: float, family: Dictionary) -> int:
	var indices := Geometry2D.triangulate_polygon(ring)
	if indices.is_empty():
		return 0
	var roof: Color = family["roof"]
	var total := 0
	for index in range(0, indices.size(), 3):
		var a := ring[indices[index]]
		var b := ring[indices[index + 1]]
		var c := ring[indices[index + 2]]
		var added := MeshBuilder._add_triangle(
			surface,
			Vector3(a.x, y, a.y),
			Vector3(b.x, y, b.y),
			Vector3(c.x, y, c.y),
			Vector3.UP,
			roof,
		)
		if added.size() == 3:
			faces.append_array(added)
			total += 1
	return total


## Rooftop plant / lift overrun: one small box near the centroid of the parcel.
func _emit_plant(surface: SurfaceTool, faces: PackedVector3Array, ring: PackedVector2Array, y: float, family: Dictionary, variant: int) -> int:
	var center := Vector2.ZERO
	for point in ring:
		center += point
	center /= ring.size()
	var size := 3.0 + float(variant % 5)
	var half := size * 0.5
	var corners := [
		center + Vector2(-half, -half), center + Vector2(half, -half),
		center + Vector2(half, half), center + Vector2(-half, half),
	]
	for corner in corners:
		if not Geometry2D.is_point_in_polygon(corner, ring):
			return 0
	var color: Color = family["roof"].lightened(0.06)
	var total := 0
	for index in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		var edge := b - a
		var outward := Vector2(edge.y, -edge.x).normalized()
		var added := _quad(
			surface, faces,
			Vector3(a.x, y, a.y), Vector3(b.x, y, b.y),
			Vector3(b.x, y + 2.2, b.y), Vector3(a.x, y + 2.2, a.y),
			Vector3(outward.x, 0.0, outward.y), color,
		)
		total += added["triangles"]
	var top := [
		Vector3(corners[0].x, y + 2.2, corners[0].y), Vector3(corners[1].x, y + 2.2, corners[1].y),
		Vector3(corners[2].x, y + 2.2, corners[2].y), Vector3(corners[3].x, y + 2.2, corners[3].y),
	]
	total += _triangle(surface, faces, top[0], top[1], top[2], Vector3.UP, color)["triangles"]
	total += _triangle(surface, faces, top[0], top[2], top[3], Vector3.UP, color)["triangles"]
	return total


func _quad(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	normal: Vector3,
	color: Color,
) -> Dictionary:
	var first := _triangle(surface, faces, p0, p1, p2, normal, color)
	var second := _triangle(surface, faces, p0, p2, p3, normal, color)
	return {
		"triangles": int(first["triangles"]) + int(second["triangles"]),
		"degenerate": int(first["degenerate"]) + int(second["degenerate"]),
	}


func _triangle(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	normal: Vector3,
	color: Color,
) -> Dictionary:
	var cross := (b - a).cross(c - a)
	if cross.length() < 0.000001:
		return {"triangles": 0, "degenerate": 1}
	var added := MeshBuilder._add_triangle(surface, a, b, c, normal, color)
	if added.size() != 3:
		return {"triangles": 0, "degenerate": 1}
	faces.append_array(added)
	return {"triangles": 1, "degenerate": 0}


## A simple hipped roof over the parcel's inscribed rectangle.
##
## Convex, rectangular-ish low-rise parcels only: an L-shaped terrace would get
## an overhanging roof if the full ring were used, so those keep the flat cap.
func _emit_pitched_roof(
	surface: SurfaceTool,
	faces: PackedVector3Array,
	ring: PackedVector2Array,
	y: float,
	family: Dictionary,
	variant: int,
) -> int:
	# Longest edge sets the ridge direction.
	var axis := Vector2.RIGHT
	var longest := 0.0
	for index in ring.size():
		var edge := ring[(index + 1) % ring.size()] - ring[index]
		if edge.length() > longest:
			longest = edge.length()
			axis = edge.normalized()
	if longest < 3.0:
		return _emit_roof(surface, faces, ring, y, family)
	var side := Vector2(-axis.y, axis.x)
	var min_u := INF
	var max_u := -INF
	var min_v := INF
	var max_v := -INF
	for point in ring:
		var u := point.dot(axis)
		var v := point.dot(side)
		min_u = minf(min_u, u)
		max_u = maxf(max_u, u)
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)
	var inset := 0.22
	min_u += inset
	max_u -= inset
	min_v += inset
	max_v -= inset
	var half_v := (max_v - min_v) * 0.5
	if max_u - min_u < 2.0 or half_v < 1.0:
		return _emit_roof(surface, faces, ring, y, family)
	# The roof is built over the parcel's bounding rectangle, so it may only be
	# used when that rectangle really is the parcel. Without this test a
	# triangular or skewed footprint got a roof far larger than its walls, which
	# read as a floating cone over the street.
	var rectangle_area := (max_u - min_u) * (max_v - min_v)
	var parcel_area := absf(MeshBuilder._signed_area(ring))
	if rectangle_area > parcel_area * 1.16:
		return _emit_roof(surface, faces, ring, y, family)
	var rise := clampf(half_v * (0.50 + float(variant % 5) * 0.03), 1.4, 3.0)
	var mid_v := (min_v + max_v) * 0.5
	var corner := func(u: float, v: float) -> Vector3:
		return Vector3(axis.x * u + side.x * v, y, axis.y * u + side.y * v)
	var a: Vector3 = corner.call(min_u, min_v)
	var b: Vector3 = corner.call(max_u, min_v)
	var c: Vector3 = corner.call(max_u, max_v)
	var d: Vector3 = corner.call(min_u, max_v)
	var r0: Vector3 = corner.call(min_u, mid_v) + Vector3(0.0, rise, 0.0)
	var r1: Vector3 = corner.call(max_u, mid_v) + Vector3(0.0, rise, 0.0)
	var slope := rise / maxf(half_v, 0.5)
	var normal_low := Vector3(-side.x, slope, -side.y).normalized()
	var normal_high := Vector3(side.x, slope, side.y).normalized()
	var roof_color: Color = family["roof"]
	var wall_color: Color = family["wall"]
	var total := 0
	# Two slopes.
	var first := _quad(surface, faces, a, b, r1, r0, normal_low, roof_color)
	var second := _quad(surface, faces, d, c, r1, r0, normal_high, roof_color.darkened(0.04))
	total += int(first["triangles"]) + int(second["triangles"])
	# Two gable ends.
	var gable_a := _triangle(surface, faces, a, r0, d, Vector3(-axis.x, 0.0, -axis.y), wall_color.darkened(0.08))
	var gable_b := _triangle(surface, faces, b, c, r1, Vector3(axis.x, 0.0, axis.y), wall_color.darkened(0.08))
	total += int(gable_a["triangles"]) + int(gable_b["triangles"])
	return total


func _is_convex(ring: PackedVector2Array) -> bool:
	if ring.size() < 3:
		return false
	var orientation := signf(MeshBuilder._signed_area(ring))
	for index in ring.size():
		var before := ring[index] - ring[(index + ring.size() - 1) % ring.size()]
		var after := ring[(index + 1) % ring.size()] - ring[index]
		if before.length() < 0.05 or after.length() < 0.05:
			return false
		if before.cross(after) * orientation < -0.01:
			return false
	return true


func _tint(color: Color, amount: float) -> Color:
	if amount >= 0.0:
		return color.lightened(amount)
	return color.darkened(-amount)


## Inward offset of a closed ring by `distance`.
##
## `Geometry2D.offset_polygon` is not used here: it can return a runaway or an
## empty result for a negative delta on a small parcel (the same defect the
## Opera House apron hit in Phase 4). This offsets each edge along its inward
## normal and intersects the two offset lines at every vertex, then rejects the
## result unless every point is inside the original ring and the area is
## plausible. A rejected inset simply means "no setback" for that building.
func _inset_ring(ring: PackedVector2Array, distance: float) -> PackedVector2Array:
	if ring.size() < 3 or distance <= 0.0:
		return PackedVector2Array()
	var count := ring.size()
	var orientation := signf(MeshBuilder._signed_area(ring))
	var out := PackedVector2Array()
	for index in count:
		var previous := ring[(index + count - 1) % count]
		var current := ring[index]
		var following := ring[(index + 1) % count]
		var incoming := current - previous
		var outgoing := following - current
		if incoming.length() < 0.05 or outgoing.length() < 0.05:
			return PackedVector2Array()
		# Inward normal: the opposite of the outward normal used for walls.
		var inward_a := -Vector2(incoming.y, -incoming.x).normalized() * orientation
		var inward_b := -Vector2(outgoing.y, -outgoing.x).normalized() * orientation
		var point_a := previous + inward_a * distance
		var point_b := current + inward_b * distance
		var denominator := incoming.cross(outgoing)
		var corner: Vector2
		if absf(denominator) < 1e-4:
			corner = current + (inward_a + inward_b).normalized() * distance
		else:
			var t := (point_b - point_a).cross(outgoing) / denominator
			corner = point_a + incoming * t
		if not Geometry2D.is_point_in_polygon(corner, ring):
			return PackedVector2Array()
		out.append(corner)
	return out
