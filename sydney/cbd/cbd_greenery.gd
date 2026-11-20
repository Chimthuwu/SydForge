extends RefCounted

## Park and street vegetation for the expanded Sydney CBD (Phase 6B).
##
## The base importer draws every OSM park polygon as one flat green surface.
## That is correct but reads as a coloured hole in the city. This builder adds
## the vegetation that makes Hyde Park, The Domain, the Royal Botanic Garden and
## the pocket parks legible from the street: trees scattered inside the real OSM
## park polygons, plus an avenue of street trees along the major CBD roads.
##
## This is presentation only. No new park polygons are invented: every tree sits
## inside an exported OSM ring, or on the derived footpath beside a real road.
## Two MultiMesh instances (trunks, canopies) draw the whole layer, and there is
## no per-frame work.
##
## Determinism: the scatter hash is seeded from the park id, so two runs produce
## identical trees and the geometry test can compare checksums.

const TREE_SPACING := 11.5
const TREE_JITTER := 4.2
const STREET_TREE_SPACING := 19.0
const STREET_TREE_OFFSET := 2.1
const MAX_PARK_TREES := 7200
const MAX_STREET_TREES := 2600
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")
const PARK_LANDMARK_CLEARINGS := [
	[Vector2(332.0, -178.0), 52.0], # Archibald Fountain
	[Vector2(270.0, -300.0), 24.0], # Hyde Park Obelisk
	[Vector2(300.0, 342.0), 40.0], # Anzac Memorial
]
const PARK_LANDMARK_PATH_X := 332.0
const PARK_LANDMARK_PATH_Z_MIN := -350.0
const PARK_LANDMARK_PATH_Z_MAX := -40.0

var stats: Dictionary = {}


func build(parks: Array, roads: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Vegetation"
	var park_trees := _park_trees(parks)
	var street_trees := _street_trees(roads)
	var trunk_mesh := _trunk_mesh()
	var canopy_mesh := _canopy_mesh()
	var trunk_count := 0
	var canopy_count := 0

	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk_mesh
	trunks.instance_count = park_trees.size() + street_trees.size()
	for index in trunks.instance_count:
		var point: Vector3 = park_trees[index] if index < park_trees.size() else street_trees[index - park_trees.size()]
		var scale := 0.82 + _hash01(index * 31 + 7) * 0.5
		# The cylinder is centred on its origin, so lift it by half its height;
		# otherwise the bottom half of every trunk is buried under the park.
		trunks.set_instance_transform(index, Transform3D(
			Basis.IDENTITY.scaled(Vector3(scale, scale, scale)),
			point + Vector3(0.0, 2.1 * scale, 0.0)))
	trunk_count = trunks.instance_count
	var trunk_instance := MultiMeshInstance3D.new()
	trunk_instance.name = "TreeTrunks"
	trunk_instance.multimesh = trunks
	root.add_child(trunk_instance)

	var canopies := MultiMesh.new()
	canopies.transform_format = MultiMesh.TRANSFORM_3D
	canopies.use_colors = true
	canopies.mesh = canopy_mesh
	canopies.instance_count = trunks.instance_count
	var greens := [
		Color("426f4b"), Color("4f7d4e"), Color("5e8656"),
		Color("3d6547"), Color("6f8d5b"), Color("557347"),
	]
	for index in canopies.instance_count:
		var point: Vector3 = park_trees[index] if index < park_trees.size() else street_trees[index - park_trees.size()]
		var hash := _hash01(index * 31 + 7)
		var scale := 0.82 + hash * 0.5
		var lean := (hash - 0.5) * 0.16
		var basis := Basis.from_euler(Vector3(lean, hash * TAU, lean * 0.7)).scaled(Vector3(scale, scale, scale))
		canopies.set_instance_transform(index, Transform3D(basis, point + Vector3(0, 4.7 * scale, 0)))
		canopies.set_instance_color(index, greens[index % greens.size()].lightened(hash * 0.16))
	canopy_count = canopies.instance_count
	var canopy_instance := MultiMeshInstance3D.new()
	canopy_instance.name = "TreeCanopies"
	canopy_instance.multimesh = canopies
	root.add_child(canopy_instance)

	stats = {
		"parkTrees": park_trees.size(),
		"streetTrees": street_trees.size(),
		"instances": trunks.instance_count,
		"trunkInstances": trunk_count,
		"canopyInstances": canopy_count,
		"meshNodes": 2,
	}
	return root


func _park_trees(parks: Array) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for park in parks:
		for ring in park.get("rings", []):
			if points.size() >= MAX_PARK_TREES:
				return points
			var polygon := PackedVector2Array()
			for point in ring:
				polygon.append(Vector2(float(point[0]), float(point[1])))
			if polygon.size() < 3:
				continue
			var area := absf(_signed_area(polygon))
			if area < 420.0:
				continue
			# Bigger parks get denser groves; a pocket park gets a handful.
			var spacing := TREE_SPACING
			if area < 2500.0:
				spacing = TREE_SPACING * 1.5
			elif area > 40000.0:
				spacing = TREE_SPACING * 0.78
			var bounds := _bounds(polygon)
			var seed := absi(str(park.get("id", "park")).hash())
			var row := 0
			var z := bounds.position.y
			while z <= bounds.end.y and points.size() < MAX_PARK_TREES:
				var x := bounds.position.x
				var column := 0
				while x <= bounds.end.x and points.size() < MAX_PARK_TREES:
					var hash := _hash01(seed + row * 7919 + column * 104729)
					var jittered := Vector2(
						x + (hash - 0.5) * TREE_JITTER,
						z + (_hash01(seed + row * 104729 + column * 7919) - 0.5) * TREE_JITTER,
					)
					if Geometry2D.is_point_in_polygon(jittered, polygon):
						if _near_landmark(jittered):
							x += spacing
							column += 1
							continue
						points.append(Vector3(jittered.x, 0.05, jittered.y))
					x += spacing
					column += 1
				z += spacing
				row += 1
	return points


func _near_landmark(point: Vector2) -> bool:
	if absf(point.x - PARK_LANDMARK_PATH_X) < 32.0 \
		and point.y >= PARK_LANDMARK_PATH_Z_MIN and point.y <= PARK_LANDMARK_PATH_Z_MAX:
		return true
	for feature: Array in PARK_LANDMARK_CLEARINGS:
		var centre: Vector2 = feature[0]
		if point.distance_to(centre) < float(feature[1]):
			return true
	return false


func _street_trees(roads: Array) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var avenues := ["arterial_major", "arterial", "collector"]
	for road in roads:
		if bool(road.get("tunnel", false)):
			continue
		if str(road.get("category", "")) not in avenues:
			continue
		if str(road.get("name", "")).is_empty():
			continue
		var path: Array = road.get("points", [])
		if path.size() < 2:
			continue
		var half := float(road.get("widthM", 8.0)) * 0.5 + STREET_TREE_OFFSET
		var offset := 0.0
		for index in range(path.size() - 1):
			var a := Vector2(float(path[index][0]), float(path[index][1]))
			var b := Vector2(float(path[index + 1][0]), float(path[index + 1][1]))
			var direction := b - a
			if direction.length() < 0.5:
				continue
			var step := direction.normalized() * STREET_TREE_SPACING
			var normal := Vector2(-direction.y, direction.x).normalized()
			var travel := offset
			while travel < direction.length():
				if points.size() >= MAX_STREET_TREES:
					return points
				var base := a + direction.normalized() * travel
				var side := 1.0 if int(absf(travel + a.x)) % 2 == 0 else -1.0
				points.append(Vector3(base.x + normal.x * half * side, 0.05, base.y + normal.y * half * side))
				travel += STREET_TREE_SPACING
			offset = maxf(0.0, travel - direction.length())
	return points


func _trunk_mesh() -> Mesh:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.16
	cylinder.bottom_radius = 0.36
	cylinder.height = 4.2
	cylinder.radial_segments = 8
	cylinder.rings = 2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6b503c")
	material.roughness = 1.0
	cylinder.material = material
	return cylinder


## A tree crown made from overlapping, slightly displaced ellipsoids. One
## shared mesh keeps the MultiMesh cheap, while the lobes give a broken
## silhouette instead of the old single faceted ball.
func _canopy_mesh() -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_lobe(surface, Vector3(0.0, 0.0, 0.0), Vector3(2.85, 2.35, 2.6), 9, 5, 1.0)
	_add_lobe(surface, Vector3(1.55, -0.35, 0.4), Vector3(1.8, 1.55, 1.7), 8, 4, 0.95)
	_add_lobe(surface, Vector3(-1.5, 0.0, -0.55), Vector3(1.7, 1.5, 1.75), 8, 4, 0.94)
	_add_lobe(surface, Vector3(0.2, 1.55, 0.1), Vector3(1.35, 1.2, 1.3), 8, 4, 1.04)
	surface.generate_normals()
	var mesh := surface.commit()
	if mesh != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, _foliage_material())
	return mesh


func _add_lobe(
	surface: SurfaceTool,
	center: Vector3,
	radii: Vector3,
	segments: int,
	rings: int,
	shade: float,
) -> void:
	var rows: Array = []
	for ring in rings + 1:
		var phi := PI * float(ring) / float(rings)
		var row: Array[Vector3] = []
		for segment in segments:
			var theta := TAU * float(segment) / float(segments)
			var direction := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var wobble := 1.0 + 0.09 * sin(direction.x * 3.1 + direction.y * 2.3) \
				+ 0.06 * cos(direction.z * 4.0 + direction.x * 1.7)
			var point := center + Vector3(
				direction.x * radii.x,
				direction.y * radii.y,
				direction.z * radii.z) * wobble
			row.append(point)
		rows.append(row)
	for ring in rings:
		for segment in segments:
			var next := (segment + 1) % segments
			var a: Vector3 = rows[ring][segment]
			var b: Vector3 = rows[ring][next]
			var c: Vector3 = rows[ring + 1][segment]
			var d: Vector3 = rows[ring + 1][next]
			_add_leaf_triangle(surface, a, b, c, center, radii, shade)
			_add_leaf_triangle(surface, b, d, c, center, radii, shade)


func _add_leaf_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	center: Vector3,
	radii: Vector3,
	shade: float,
) -> void:
	if (b - a).cross(c - a).length() < 0.00001:
		return
	for point in [a, b, c]:
		var up := clampf((point.y - center.y + radii.y) / (radii.y * 2.0), 0.0, 1.0)
		var tone := clampf(0.58 + up * 0.42, 0.55, 1.05) * shade
		surface.set_color(Color(tone, tone, tone))
		surface.add_vertex(point)


func _foliage_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = FOLIAGE_SHADER
	return material


func _bounds(polygon: PackedVector2Array) -> Rect2:
	var min_point := polygon[0]
	var max_point := polygon[0]
	for point in polygon:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
	return Rect2(min_point, max_point - min_point)


func _signed_area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


func _hash01(value: int) -> float:
	var state := (value * 6364136223846793005 + 1442695040888963407) & ((1 << 63) - 1)
	state = (state ^ (state >> 29)) * 0x9E3779B1 & ((1 << 63) - 1)
	return float(state & 0x7FFFFFFF) / float(0x7FFFFFFF)
