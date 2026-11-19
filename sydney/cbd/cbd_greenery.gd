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
		var scale := 0.82 + _hash01(trunks.instance_count * 17 + index) * 0.5
		trunks.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3(scale, scale, scale)), point))
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
	var greens := [Color("4a8a5c"), Color("3f7f55"), Color("5a9963"), Color("6aa86a"), Color("487d4e")]
	for index in canopies.instance_count:
		var point: Vector3 = park_trees[index] if index < park_trees.size() else street_trees[index - park_trees.size()]
		var hash := _hash01(index * 31 + 7)
		var scale := 0.85 + hash * 0.55
		var lean := (hash - 0.5) * 0.12
		var basis := Basis.from_euler(Vector3(lean, hash * TAU, lean * 0.7)).scaled(Vector3(scale, scale, scale))
		canopies.set_instance_transform(index, Transform3D(basis, point + Vector3(0, 4.4 * scale, 0)))
		canopies.set_instance_color(index, greens[index % greens.size()].lightened(hash * 0.12))
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
	cylinder.bottom_radius = 0.28
	cylinder.height = 3.6
	cylinder.radial_segments = 6
	cylinder.rings = 1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("7d5f47")
	material.roughness = 1.0
	cylinder.material = material
	return cylinder


func _canopy_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 2.5
	sphere.height = 4.6
	sphere.radial_segments = 7
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 0.95
	sphere.material = material
	return sphere


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
