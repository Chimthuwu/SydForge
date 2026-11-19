class_name AnzacBridgeLandmark
extends Node3D

## Authored Anzac Bridge structure (Phase 6C, Inner West).
##
## The deck itself comes from the real OSM way (rendered and made drivable by
## the Inner West road system: draped deck, side barriers, convex deck slabs).
## This node adds the recognisable silhouette on top: two tapered concrete
## towers in the median and the planes of stay cables fanning down to the deck,
## plus backstays. Dimensions are a stylised approximation of the real bridge
## (main span ~180 m, towers ~60 m above the deck), explicitly not a fabrication
## model; the geographic placement follows the mapped carriageway.


## Known Anzac Bridge centre (WGS84) used to find the mapped deck way.
const ANZAC_LAT := -33.8688
const ANZAC_LON := 151.1947

const TOWER_HEIGHT_M := 60.0
const TOWER_BASE_WIDTH_M := 5.0
const TOWER_TOP_WIDTH_M := 2.8
const CABLE_THICKNESS_M := 0.17
const STAY_SPACING_M := 11.5
const BACKSTAY_OFFSETS_M := [16.0, 34.0, 52.0]

var stats: Dictionary = {}


## Locate the Anzac Bridge carriageway and build the structure over it.
func build_from_world(world: InnerWestWorld) -> Dictionary:
	var road := _find_deck(world)
	if road.is_empty():
		return {"ok": false, "reason": "no Anzac Bridge carriageway found in the district data"}
	return build(road, world.height_grid)


func _find_deck(world: InnerWestWorld) -> Dictionary:
	var proj_x := (ANZAC_LON - 151.208) * 92459.893
	var proj_z := -(ANZAC_LAT + 33.873) * 111019.656
	var centre := Vector2(proj_x, proj_z)
	var best := {}
	var best_score := INF
	for road in world.data.get("roads", []):
		if not road.get("bridge", false):
			continue
		var points: Array = road.get("points", [])
		if points.size() < 4:
			continue
		var name := String(road.get("name", "")).to_lower()
		var mid := Vector2(
			(float(points[0][0]) + float(points[points.size() / 2][0])) * 0.5,
			(float(points[0][1]) + float(points[points.size() / 2][1])) * 0.5,
		)
		var distance := mid.distance_to(centre)
		var length := _polyline_length(points)
		var score := distance - (length * 0.5 if "anzac" in name else 0.0) - length * 0.02
		if score < best_score:
			best_score = score
			best = road
	if best_score > 400.0:
		return {}
	return best


func build(road: Dictionary, grid: Dictionary) -> Dictionary:
	var points: Array = road.get("points", [])
	if points.size() < 4:
		return {"ok": false, "reason": "deck polyline too short"}
	var ys := InnerWestMesh.height_along(grid, points)
	if road.get("bridge", false):
		# prefer the elevated deck profile when the road is a mapped bridge
		ys = InnerWestMesh.bridge_deck_ys(grid, points, 24.0, -0.38)

	# arc-length parameterisation of the deck centreline
	var total := _polyline_length(points)
	var tower_positions := [
		_point_at(points, ys, total * 0.26),
		_point_at(points, ys, total * 0.74),
	]
	if tower_positions[0].is_empty() or tower_positions[1].is_empty():
		return {"ok": false, "reason": "could not place towers"}

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var concrete := Color("c3c8cc")
	var concrete_dark := Color("aab0b5")
	var cable_color := Color("3d4146")

	var towers := 0
	var cables := 0
	var cable_endpoints: Array = []
	for tower in tower_positions:
		var base: Vector3 = tower["point"]
		var top: Vector3 = base + Vector3.UP * TOWER_HEIGHT_M
		_add_tapered_tower(surface, base, top, TOWER_BASE_WIDTH_M, TOWER_TOP_WIDTH_M, concrete, concrete_dark)
		# deck-level crossbeam
		var deck_point: Vector3 = tower["point"]
		_add_box(
			surface,
			deck_point + Vector3(0, 1.6, 0),
			Vector3(TOWER_BASE_WIDTH_M + 1.2, 1.3, 2.2),
			concrete_dark,
		)
		towers += 1
		cable_endpoints.append([base, top, tower])

	# stay cables: each tower fans forward to midspan and back via backstays
	var mid := _point_at(points, ys, total * 0.5)
	if not mid.is_empty():
		for entry in cable_endpoints:
			var base: Vector3 = entry[0]
			var top: Vector3 = entry[1]
			var tower: Dictionary = entry[2]
			var direction: Vector3 = mid["point"] - base
			direction.y = 0.0
			if direction.length() < 1.0:
				continue
			direction = direction.normalized()
			var forward := clampf(direction.dot(Vector3(1, 0, 0)), -1.0, 1.0)
			_ = forward
			var perp := Vector3(-direction.z, 0.0, direction.x)
			var side := 1.0 if tower["s"] < total * 0.5 else -1.0
			var anchor_distance := total * 0.24
			var count := int(anchor_distance / STAY_SPACING_M)
			for index in range(1, count + 1):
				var distance_along := STAY_SPACING_M * float(index) * side
				var anchor := _point_at_offset(tower, points, ys, distance_along)
				if anchor.is_empty():
					continue
				_add_cable(surface, top, anchor["point"], CABLE_THICKNESS_M, cable_color)
				cables += 1
			for offset in BACKSTAY_OFFSETS_M:
				var anchor := _point_at_offset(tower, points, ys, -offset * side)
				if anchor.is_empty():
					continue
				_add_cable(surface, top, anchor["point"], CABLE_THICKNESS_M, cable_color)
				cables += 1

	var mesh := InnerWestMesh.commit(surface, InnerWestMesh.vertex_mat())
	if mesh == null:
		return {"ok": false, "reason": "structure mesh is empty"}
	var instance := MeshInstance3D.new()
	instance.name = "AnzacStructure"
	instance.mesh = mesh
	add_child(instance)
	stats = {
		"towers": towers,
		"cables": cables,
		"deckPoints": points.size(),
		"spanM": total,
	}
	return {"ok": true}


# ---------------------------------------------------------------- helpers --
func _polyline_length(points: Array) -> float:
	var total := 0.0
	for index in range(points.size() - 1):
		total += Vector2(float(points[index][0]), float(points[index][1])).distance_to(
			Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
		)
	return total


func _point_at(points: Array, ys: PackedFloat32Array, target_length: float) -> Dictionary:
	var walked := 0.0
	for index in range(points.size() - 1):
		var a := Vector2(float(points[index][0]), float(points[index][1]))
		var b := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
		var segment := a.distance_to(b)
		if walked + segment >= target_length:
			var t := 0.0 if segment < 1e-6 else (target_length - walked) / segment
			var point := a.lerp(b, t)
			var y := lerpf(ys[index], ys[index + 1], t)
			return {"point": Vector3(point.x, y, point.y), "s": walked}
		walked += segment
	return {}


func _point_at_offset(tower: Dictionary, points: Array, ys: PackedFloat32Array, offset: float) -> Dictionary:
	return _point_at(points, ys, float(tower["s"]) + offset)


func _add_tapered_tower(
	surface: SurfaceTool, base: Vector3, top: Vector3,
	base_width: float, top_width: float, color: Color, dark: Color,
) -> void:
	# 4-sided tapered shaft: two sizes of box blended by shearing the top ring
	var half_base := base_width * 0.5
	var half_top := top_width * 0.5
	var bottom := [
		base + Vector3(-half_base, 0, -half_base), base + Vector3(half_base, 0, -half_base),
		base + Vector3(half_base, 0, half_base), base + Vector3(-half_base, 0, half_base),
	]
	var upper := [
		top + Vector3(-half_top, 0, -half_top), top + Vector3(half_top, 0, -half_top),
		top + Vector3(half_top, 0, half_top), top + Vector3(-half_top, 0, half_top),
	]
	for index in 4:
		var a := bottom[index]
		var b := bottom[(index + 1) % 4]
		var c := upper[(index + 1) % 4]
		var d := upper[index]
		var edge_normal: Vector3 = (b - a).cross(Vector3.UP) * -1.0
		if edge_normal.length() < 0.000001:
			edge_normal = Vector3(0, 0, 1)
		InnerWestMesh.tri(surface, a, b, c, edge_normal.normalized(), color)
		InnerWestMesh.tri(surface, a, c, d, edge_normal.normalized(), color)
	# top cap
	InnerWestMesh.tri(surface, upper[3], upper[2], upper[1], Vector3.UP, dark)
	InnerWestMesh.tri(surface, upper[3], upper[1], upper[0], Vector3.UP, dark)
	# aviation lamp block
	var cap_centre := (upper[0] + upper[2]) * 0.5
	_add_box(surface, cap_centre + Vector3(0, 0.9, 0), Vector3(0.6, 1.8, 0.6), Color("b8412f"))


func _add_box(surface: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var half := size * 0.5
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
		InnerWestMesh.tri(surface, corners[quad[0]], corners[quad[1]], corners[quad[2]], normal, color)
		InnerWestMesh.tri(surface, corners[quad[0]], corners[quad[2]], corners[quad[3]], normal, color)
	InnerWestMesh.tri(surface, corners[3], corners[2], corners[6], Vector3.UP, color)
	InnerWestMesh.tri(surface, corners[3], corners[6], corners[7], Vector3.UP, color)


func _add_cable(surface: SurfaceTool, from: Vector3, to: Vector3, thickness: float, color: Color) -> void:
	var direction := (to - from).normalized()
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var helper := Vector3(0, 1, 0) if absf(direction.y) < 0.9 else Vector3(1, 0, 0)
	var u := helper.cross(direction).normalized() * thickness * 0.5
	var v := direction.cross(u).normalized() * thickness * 0.5
	var a0 := from + u + v
	var a1 := from - u + v
	var a2 := from - u - v
	var a3 := from + u - v
	var b0 := to + u + v
	var b1 := to - u + v
	var b2 := to - u - v
	var b3 := to + u - v
	var faces := [
		[a0, a1, b1, b0], [a1, a2, b2, b1], [a2, a3, b3, b2], [a3, a0, b0, b3],
	]
	for face in faces:
		var normal: Vector3 = (face[1] - face[0]).cross(face[3] - face[0])
		if normal.length() < 0.000001:
			continue
		normal = normal.normalized()
		InnerWestMesh.tri(surface, face[0], face[1], face[2], normal, color)
		InnerWestMesh.tri(surface, face[0], face[2], face[3], normal, color)
