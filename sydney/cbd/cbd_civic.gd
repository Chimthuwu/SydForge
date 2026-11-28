extends Node3D

## Authored hero detail for Sydney's civic landmarks.
##
## The Stage B data owns every real footprint. This module adds the architecture
## those flat OSM masses cannot describe: Town Hall's portico, mansard roof and
## clock tower; Hyde Park's formal paths, fountain, obelisk and Anzac Memorial;
## Circular Quay's ferry wharves and promenade; and Darling Harbour's boardwalk,
## waterfront pavilions and Pyrmont Bridge truss.
##
## All coordinates are the installed Sydney metre projection. Geometry is
## presentation only; collision remains with the shared building importer except
## for the retained Town Hall OSM mass, which gets its own exact collision.

const ArtUtil := preload("res://scripts/art.gd")
const SydneyMeshBuilder := preload("res://sydney/sydney_mesh.gd")

const STONE := Color("c8b795")
const STONE_LIGHT := Color("ded0b5")
const STONE_DARK := Color("96866e")
const SANDSTONE := Color("c3ad8e")
const SLATE := Color("46545a")
const COPPER := Color("567b6a")
const GLASS := Color("2c4149")
const GOLD := Color("c9a75b")
const TIMBER := Color("6b5038")
const DARK_TIMBER := Color("4b392b")
const WATER := Color("315f6b")
const METAL := Color("4b585b")
const BRONZE := Color("4f5f4b")
const WARM_LIGHT := Color("ffcf8a")

var stats: Dictionary = {}
var _materials: Dictionary = {}


const HydeParkLayout := preload("res://sydney/cbd/hyde_park_layout.gd")

## Where the Hyde Park benches ended up, for the layout regression.
var bench_spots: Array[Vector2] = []
var _roads: Array = []
var _hyde_rings: Array = []


func build(world_data: Dictionary) -> void:
	name = "SydneyCivicLandmarks"
	_build_town_hall(world_data)
	_roads = world_data.get("roads", [])
	_hyde_rings.clear()
	for park: Dictionary in world_data.get("parks", []):
		if str(park.get("id", "")) in HydeParkLayout.PARK_IDS:
			for ring: Array in park.get("rings", []):
				var polygon := PackedVector2Array()
				for point: Array in ring:
					polygon.append(Vector2(float(point[0]), float(point[1])))
				_hyde_rings.append(polygon)
	_build_hyde_park()
	_build_circular_quay(world_data)
	_build_darling_harbour(world_data)
	stats = {
		"townHall": true,
		"hydePark": true,
		"circularQuayWharves": _count_children("CircularQuayLandmarks"),
		"darlingHarbourWharves": _count_children("DarlingHarbourLandmarks"),
		"pyrmontBridge": true,
		"renderMeshNodes": _render_mesh_count(self),
	}


func _group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	add_child(group)
	return group


func _count_children(group_name: String) -> int:
	var group := get_node_or_null(group_name)
	return group.get_child_count() if group != null else 0


func _row(world_data: Dictionary, wanted_id: String) -> Dictionary:
	for row: Dictionary in world_data.get("buildings", []):
		if String(row.get("id", "")) == wanted_id:
			return row
	return {}


func _ring_bounds(row: Dictionary) -> Rect2:
	var ring: Array = row.get("ring", [])
	if ring.is_empty():
		return Rect2()
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	for point: Array in ring:
		min_x = minf(min_x, float(point[0]))
		min_z = minf(min_z, float(point[1]))
		max_x = maxf(max_x, float(point[0]))
		max_z = maxf(max_z, float(point[1]))
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))


func _ring_center(row: Dictionary) -> Vector2:
	var ring: Array = row.get("ring", [])
	var center := Vector2.ZERO
	for point: Array in ring:
		center += Vector2(float(point[0]), float(point[1]))
	return center / maxf(1.0, float(ring.size()))


func _add_mass(parent: Node3D, row: Dictionary, tint: Color) -> void:
	var result: Dictionary = SydneyMeshBuilder.buildings([row])
	var source_mesh: ArrayMesh = result.get("mesh")
	if source_mesh == null:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "OSMFootprintMass"
	mesh.mesh = SydneyMeshBuilder.engine_building_mesh(source_mesh)
	mesh.material_override = ArtUtil.mat(tint)
	parent.add_child(mesh)
	var faces: PackedVector3Array = SydneyMeshBuilder.engine_building_faces(
		result.get("faces", PackedVector3Array())
	)
	if faces.size() < 3:
		return
	var body := StaticBody3D.new()
	body.name = "LandmarkCollision"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


## A local facade space: local X runs along the wall, local +Z points at the
## street. Everything on that elevation is authored in this frame.
func _facade(parent: Node3D, position: Vector3, outward: Vector3, node_name: String = "Facade") -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	node.rotation.y = atan2(outward.x, outward.z)
	parent.add_child(node)
	return node


func _box(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	return ArtUtil.box(parent, position, size, color)


func _window(
	parent: Node3D,
	x: float,
	y: float,
	width: float,
	height: float,
	glass: Color = GLASS,
	frame: Color = STONE_LIGHT,
) -> void:
	_box(parent, Vector3(x, y + height * 0.5, 0.06), Vector3(width, height, 0.12), glass)
	_box(parent, Vector3(x, y - 0.09, 0.16), Vector3(width + 0.44, 0.20, 0.34), frame)
	_box(parent, Vector3(x, y + height + 0.12, 0.14), Vector3(width + 0.40, 0.22, 0.28), frame)
	_box(parent, Vector3(x, y + height + 0.30, 0.17), Vector3(0.34, 0.36, 0.20), frame.darkened(0.08))
	for side in [-1.0, 1.0]:
		_box(parent, Vector3(x + side * (width * 0.5 + 0.11), y + height * 0.5, 0.12), Vector3(0.20, height, 0.24), frame)
	_box(parent, Vector3(x, y + height * 0.55, 0.13), Vector3(0.08, height * 0.9, 0.06), frame.darkened(0.18))
	_box(parent, Vector3(x, y + height * 0.5, 0.13), Vector3(width * 0.9, 0.07, 0.06), frame.darkened(0.18))


func _pilaster(parent: Node3D, x: float, y0: float, y1: float, color: Color = STONE_LIGHT) -> void:
	_box(parent, Vector3(x, (y0 + y1) * 0.5, 0.16), Vector3(0.48, y1 - y0, 0.34), color)
	_box(parent, Vector3(x, y0 + 0.18, 0.20), Vector3(0.66, 0.30, 0.46), color.darkened(0.10))
	_box(parent, Vector3(x, y1 - 0.12, 0.20), Vector3(0.62, 0.24, 0.44), color.darkened(0.06))


func _balustrade(parent: Node3D, width: float, y: float, spacing: float = 2.6) -> void:
	_box(parent, Vector3(0.0, y + 1.05, 0.20), Vector3(width, 0.16, 0.42), STONE_LIGHT)
	_box(parent, Vector3(0.0, y + 0.12, 0.20), Vector3(width, 0.22, 0.50), STONE)
	var count := maxi(2, int(width / spacing))
	for index in count + 1:
		var x := -width * 0.5 + width * float(index) / float(count)
		_box(parent, Vector3(x, y + 0.58, 0.20), Vector3(0.20, 0.90, 0.30), STONE_LIGHT)


func _gable(parent: Node3D, position: Vector3, width: float, height: float, depth: float, color: Color) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var hd := depth * 0.5
	var front := [
		Vector3(-hw, 0.0, hd), Vector3(hw, 0.0, hd), Vector3(0.0, height, hd),
	]
	var back := [
		Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd), Vector3(0.0, height, -hd),
	]
	for point in front:
		surface.set_normal(Vector3.BACK)
		surface.add_vertex(point)
	for point in [back[0], back[1], back[2]]:
		surface.set_normal(Vector3.FORWARD)
		surface.add_vertex(point)
	# Slopes.
	var left_n := Vector3(-height, hw, 0.0).normalized()
	var right_n := Vector3(height, hw, 0.0).normalized()
	for point in [front[0], back[0], back[2], front[0], back[2], front[2]]:
		surface.set_normal(left_n)
		surface.add_vertex(point)
	for point in [front[1], front[2], back[2], front[1], back[2], back[1]]:
		surface.set_normal(right_n)
		surface.add_vertex(point)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = ArtUtil.mat(color)
	parent.add_child(instance)
	instance.position = position
	return instance


func _build_town_hall(world_data: Dictionary) -> void:
	var row := _row(world_data, "way/104948253")
	if row.is_empty():
		return
	var group := _group("SydneyTownHall")
	var bounds := _ring_bounds(row)
	var center := _ring_center(row)
	var height := float(row.get("heightM", 12.8))
	var x0 := bounds.position.x
	var x1 := bounds.end.x
	var z0 := bounds.position.y
	var z1 := bounds.end.y
	_add_mass(group, row, SANDSTONE)

	# The four street elevations. The main civic entrance faces George Street
	# (east); the long Bathurst/Druitt sides carry the repetitive bays.
	var east := _facade(group, Vector3(x1, 0.0, center.y), Vector3.RIGHT, "GeorgeStreetElevation")
	var west := _facade(group, Vector3(x0, 0.0, center.y), Vector3.LEFT, "DarlingHarbourElevation")
	var south := _facade(group, Vector3(center.x, 0.0, z1), Vector3.BACK, "BathurstStreetElevation")
	var north := _facade(group, Vector3(center.x, 0.0, z0), Vector3.FORWARD, "DruittStreetElevation")

	var east_width := z1 - z0
	var long_width := x1 - x0
	for facade: Node3D in [east, west, south, north]:
		var width := east_width if facade == east or facade == west else long_width
		# Rusticated sandstone base and the storey cornice.
		for band in 4:
			_box(facade, Vector3(0.0, 0.42 + float(band) * 0.72, 0.12), Vector3(width + 0.2, 0.15, 0.26), SANDSTONE.darkened(0.10))
		_box(facade, Vector3(0.0, height * 0.49, 0.14), Vector3(width + 0.3, 0.28, 0.30), STONE_LIGHT)
		_box(facade, Vector3(0.0, height + 0.10, 0.18), Vector3(width + 0.7, 0.55, 0.48), STONE_LIGHT)
		_balustrade(facade, width + 0.3, height + 0.42, 2.8)

	# Long elevations: eleven bays, two storeys, paired pilasters.
	for facade: Node3D in [south, north, west]:
		var width := long_width - 4.0
		var bays := 9
		for index in bays + 1:
			var x := -width * 0.5 + width * float(index) / float(bays)
			_pilaster(facade, x, 0.0, height * 0.88)
		for index in bays:
			var x := -width * 0.5 + width * (float(index) + 0.5) / float(bays)
			_window(facade, x, 2.6, 2.05, 3.55)
			_window(facade, x, 8.35, 1.55, 2.75)
	# A central pedimented entrance on the long south side, as on Bathurst St.
	_gable(south, Vector3(0.0, height + 0.62, 0.55), 15.0, 3.4, 1.4, STONE_LIGHT)
	var south_label := ArtUtil.label(south, Vector3(0.0, height + 1.35, 0.86), "TOWN HALL", 54)
	south_label.modulate = Color("6f5c42")
	south_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# George Street front: pilasters, tall windows, and the six-column portico.
	var east_bays := 7
	for index in east_bays + 1:
		var x := -(east_width - 3.0) * 0.5 + (east_width - 3.0) * float(index) / float(east_bays)
		if absf(x) > 10.0:
			_pilaster(east, x, 0.0, height * 0.88)
	for index in east_bays:
		var x := -(east_width - 3.0) * 0.5 + (east_width - 3.0) * (float(index) + 0.5) / float(east_bays)
		if absf(x) < 12.0:
			continue
		_window(east, x, 2.7, 2.15, 3.4)
		_window(east, x, 8.4, 1.65, 2.65)

	# Grand steps, six columns, entablature and pediment.
	for step in 6:
		var step_width := 32.0 - float(step) * 0.55
		_box(east, Vector3(0.0, 0.10 + float(step) * 0.16, 6.6 - float(step) * 0.86), Vector3(step_width, 0.16, 0.94), STONE_LIGHT.darkened(0.04))
	_box(east, Vector3(0.0, 0.42, 1.1), Vector3(32.0, 0.84, 4.9), SANDSTONE.darkened(0.08))
	for index in 6:
		var x := -12.5 + float(index) * 5.0
		ArtUtil.cylinder(east, Vector3(x, 5.8, 3.4), 0.62, 9.6, STONE_LIGHT)
		_box(east, Vector3(x, 0.86, 3.4), Vector3(1.62, 0.38, 1.62), STONE_LIGHT.darkened(0.06))
		_box(east, Vector3(x, 10.45, 3.4), Vector3(1.72, 0.42, 1.72), STONE_LIGHT)
		_box(east, Vector3(x, 10.2, 3.4), Vector3(1.28, 0.32, 1.28), STONE_LIGHT.lightened(0.06))
	_box(east, Vector3(0.0, 11.0, 3.1), Vector3(31.0, 1.10, 4.7), STONE_LIGHT)
	_box(east, Vector3(0.0, 11.8, 3.1), Vector3(31.8, 0.52, 5.1), STONE_LIGHT.lightened(0.04))
	_gable(east, Vector3(0.0, 12.1, 3.35), 31.0, 4.1, 4.2, STONE_LIGHT)
	var entrance_label := ArtUtil.label(east, Vector3(0.0, 11.55, 5.55), "SYDNEY TOWN HALL", 64)
	entrance_label.modulate = Color("6c583d")
	entrance_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	for index in 3:
		var x := (float(index) - 1.0) * 6.2
		_box(east, Vector3(x, 2.1, 0.25), Vector3(2.8, 3.4, 0.24), Color("2d2923"))
		_box(east, Vector3(x, 3.95, 0.36), Vector3(3.3, 0.34, 0.34), STONE_LIGHT)
		_box(east, Vector3(x, 0.55, 0.30), Vector3(3.2, 0.22, 0.42), STONE)
	# Entrance lamps.
	for x in [-8.5, 8.5]:
		ArtUtil.cylinder(east, Vector3(x, 2.2, 6.7), 0.14, 3.6, METAL)
		ArtUtil.sphere(east, Vector3(x, 4.15, 6.7), 0.36, WARM_LIGHT)

	# Mansard roof: four inward-sloping planes, a flat deck and dormers.
	_box(group, Vector3(center.x, height + 0.90, center.y), Vector3(x1 - x0 - 1.2, 0.7, z1 - z0 - 1.2), SLATE)
	for side in [-1.0, 1.0]:
		var roof_south := ArtUtil.box(group, Vector3(center.x, height + 3.35, center.y + side * (z1 - z0) * 0.5 - side * 2.6), Vector3(x1 - x0 + 0.4, 0.55, 6.8), SLATE)
		roof_south.rotation.x = -side * 0.55
		var roof_east := ArtUtil.box(group, Vector3(center.x + side * (x1 - x0) * 0.5 - side * 2.6, height + 3.35, center.y), Vector3(6.8, 0.55, z1 - z0 + 0.4), SLATE)
		roof_east.rotation.z = side * 0.55
	_box(group, Vector3(center.x, height + 6.1, center.y), Vector3(x1 - x0 - 13.0, 0.8, z1 - z0 - 13.0), SLATE.darkened(0.10))

	# Dormers, paired along the long sides and on George Street.
	for side in [-1.0, 1.0]:
		for index in 5:
			var x: float = lerpf(x0 + 14.0, x1 - 14.0, float(index) / 4.0)
			var z: float = center.y + float(side) * (z1 - z0) * 0.5 - float(side) * 3.1
			_box(group, Vector3(x, height + 3.15, z), Vector3(2.4, 2.3, 1.6), STONE_LIGHT)
			ArtUtil.box(group, Vector3(x, height + 3.0, z + side * 0.82), Vector3(1.4, 1.55, 0.12), GLASS)
			_gable(group, Vector3(x, height + 4.3, z), 2.8, 1.1, 1.8, STONE_LIGHT)
		for index in 4:
			var x: float = center.x + float(side) * (x1 - x0) * 0.5 - float(side) * 3.1
			var z: float = lerpf(z0 + 13.0, z1 - 13.0, float(index) / 3.0)
			_box(group, Vector3(x, height + 3.15, z), Vector3(1.6, 2.3, 2.4), STONE_LIGHT)
			ArtUtil.box(group, Vector3(x + side * 0.82, height + 3.0, z), Vector3(0.12, 1.55, 1.4), GLASS)
			_gable(group, Vector3(x, height + 4.3, z), 1.8, 1.1, 2.8, STONE_LIGHT)

	# Corner pavilions.
	for x in [x0 + 4.8, x1 - 4.8]:
		for z in [z0 + 4.8, z1 - 4.8]:
			_box(group, Vector3(x, height + 1.6, z), Vector3(9.4, 3.2, 9.4), STONE_LIGHT)
			_box(group, Vector3(x, height + 3.25, z), Vector3(10.2, 0.42, 10.2), STONE_LIGHT.lightened(0.05))
			ArtUtil.tapered_box(group, Vector3(x, height + 4.75, z), Vector3(8.8, 2.7, 8.8), Vector2(0.9, 0.9), SLATE)
			ArtUtil.cylinder(group, Vector3(x, height + 6.3, z), 0.35, 1.4, GOLD, 0.08)

	# Clock tower: staged sandstone shaft, clock faces, belfry and copper cap.
	var tower_center := Vector3(center.x, 0.0, center.y)
	_box(group, tower_center + Vector3(0.0, height + 1.4, 0.0), Vector3(16.0, 3.4, 16.0), STONE_LIGHT)
	_box(group, tower_center + Vector3(0.0, height + 3.2, 0.0), Vector3(16.6, 0.50, 16.6), STONE_LIGHT.lightened(0.05))
	_box(group, tower_center + Vector3(0.0, height + 14.0, 0.0), Vector3(11.8, 22.0, 11.8), SANDSTONE.lightened(0.04))
	for x in [-5.0, 5.0]:
		for z in [-5.0, 5.0]:
			_box(group, tower_center + Vector3(x, height + 14.0, z), Vector3(1.15, 22.4, 1.15), STONE_LIGHT)
	for level in [7.0, 13.0, 19.0]:
		for face in 4:
			var angle := float(face) * PI * 0.5
			var normal := Vector3(sin(angle), 0.0, cos(angle))
			var pos := tower_center + Vector3(0.0, height + level, 0.0) + normal * 6.02
			var pane := ArtUtil.box(group, pos, Vector3(1.15, 3.3, 0.11), GLASS)
			pane.rotation.y = angle
			var hood := ArtUtil.box(group, pos + Vector3(0.0, 1.75, 0.0), Vector3(1.55, 0.28, 0.24), STONE_LIGHT)
			hood.rotation.y = angle
	_box(group, tower_center + Vector3(0.0, height + 25.4, 0.0), Vector3(13.4, 0.62, 13.4), STONE_LIGHT)
	_box(group, tower_center + Vector3(0.0, height + 29.0, 0.0), Vector3(12.8, 6.4, 12.8), STONE_LIGHT)
	for face in 4:
		var angle := float(face) * PI * 0.5
		var normal := Vector3(sin(angle), 0.0, cos(angle))
		var clock_center := tower_center + Vector3(0.0, height + 29.0, 0.0) + normal * 6.5
		_add_clock_face(group, clock_center, 3.05, angle)
	# Belfry openings and corner pinnacles.
	for face in 4:
		var angle := float(face) * PI * 0.5
		var normal := Vector3(sin(angle), 0.0, cos(angle))
		var opening := ArtUtil.box(group, tower_center + Vector3(0.0, height + 35.6, 0.0) + normal * 5.05, Vector3(2.4, 5.2, 0.22), Color("252b2c"))
		opening.rotation.y = angle
		var arch_top := ArtUtil.cylinder(group, tower_center + Vector3(0.0, height + 38.2, 0.0) + normal * 5.12, 1.2, 0.22, Color("252b2c"))
		arch_top.rotation.x = PI * 0.5
		arch_top.rotation.y = angle
	for x in [-4.5, 4.5]:
		for z in [-4.5, 4.5]:
			ArtUtil.cylinder(group, tower_center + Vector3(x, height + 34.5, z), 0.65, 2.2, STONE_LIGHT)
			ArtUtil.cylinder(group, tower_center + Vector3(x, height + 37.0, z), 0.40, 3.0, SLATE, 0.05)
	_box(group, tower_center + Vector3(0.0, height + 38.8, 0.0), Vector3(11.2, 0.45, 11.2), STONE_LIGHT.lightened(0.06))
	ArtUtil.tapered_box(group, tower_center + Vector3(0.0, height + 42.5, 0.0), Vector3(10.8, 7.0, 10.8), Vector2(2.1, 2.1), COPPER)
	ArtUtil.cylinder(group, tower_center + Vector3(0.0, height + 46.6, 0.0), 0.38, 3.0, GOLD, 0.06)
	ArtUtil.sphere(group, tower_center + Vector3(0.0, height + 48.4, 0.0), 0.34, GOLD)


func _add_clock_face(parent: Node3D, center: Vector3, radius: float, angle: float) -> void:
	var normal := Vector3(sin(angle), 0.0, cos(angle))
	var disk := ArtUtil.cylinder(parent, center, radius, 0.30, Color("3a403e"))
	var face := ArtUtil.cylinder(parent, center + normal * 0.20, radius * 0.82, 0.14, STONE_LIGHT)
	disk.rotation.x = PI * 0.5
	face.rotation.x = PI * 0.5
	disk.rotation.y = angle
	face.rotation.y = angle
	var hand := ArtUtil.box(parent, center + normal * 0.32, Vector3(0.10, radius * 0.68, 0.08), Color("2e3533"))
	hand.rotation.y = angle
	hand.position += Vector3(0.0, radius * 0.25, 0.0)
	var hand_short := ArtUtil.box(parent, center + normal * 0.32, Vector3(radius * 0.46, 0.10, 0.08), Color("2e3533"))
	hand_short.rotation.y = angle


func _build_hyde_park() -> void:
	var group := _group("HydeParkLandmarks")
	var axis_x := HydeParkLayout.FOUNTAIN.x
	var north_edge := -332.0
	var south_edge := 405.0
	var fountain_z := HydeParkLayout.FOUNTAIN.y

	# The OSM walkways inside the park arrive as road ribbons and were drawn as
	# black asphalt. Pave over them, then lay the authored avenue and walks.
	var paving := Color("b9a98c")
	for road: Dictionary in _roads:
		if str(road.get("highway", "")) != "pedestrian":
			continue
		var points: Array = road.get("points", [])
		for i in range(points.size() - 1):
			var a := Vector2(float(points[i][0]), float(points[i][1]))
			var b := Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
			if _in_hyde_park((a + b) * 0.5):
				_paving_strip(group, a, b, float(road.get("widthM", 8.0)) + 0.4, 0.14, paving)
	var height := 0.155
	for path: Array in HydeParkLayout.paths():
		_paving_strip(group, path[0], path[1], float(path[2]), height, paving.lightened(0.06))
		height += 0.002  # crossings of two walks must not z-fight

	# Benches sit just off the paving, facing it, and never near a road.
	for path: Array in HydeParkLayout.paths():
		var a: Vector2 = path[0]
		var b: Vector2 = path[1]
		var along := (b - a).normalized()
		var side := Vector2(-along.y, along.x)
		var travel := 14.0
		var flip := 1.0
		while travel < a.distance_to(b) - 10.0:
			var spot := a + along * travel + side * flip * (float(path[2]) * 0.5 + 0.7)
			if _in_hyde_park(spot) and not HydeParkLayout.on_monument(spot, 0.0) \
			and not HydeParkLayout.near_road(spot, _roads, 3.0):
				var facing := -side * flip
				_bench(group, Vector3(spot.x, 0.0, spot.y), atan2(facing.x, facing.y))
				bench_spots.append(spot)
			travel += 26.0
			flip = -flip
	for lamp_z in [fountain_z - 27.0, fountain_z + 27.0]:
		for lamp_x in [axis_x - 15.0, axis_x + 15.0]:
			_park_lamp(group, Vector3(lamp_x, 0.0, lamp_z))

	# Archibald Fountain: broad paved apron, two basins, bronze group and jets.
	var apron := ArtUtil.cylinder(group, Vector3(axis_x, 0.13, fountain_z), 18.0, 0.22, STONE_LIGHT.darkened(0.08))
	apron.name = "FountainApron"
	ArtUtil.cylinder(group, Vector3(axis_x, 0.58, fountain_z), 13.2, 1.05, STONE)
	_cylinder_material(group, Vector3(axis_x, 1.13, fountain_z), 12.3, 0.14, _water_material())
	ArtUtil.cylinder(group, Vector3(axis_x, 1.55, fountain_z), 7.2, 0.72, STONE_LIGHT)
	_cylinder_material(group, Vector3(axis_x, 1.94, fountain_z), 6.5, 0.16, _water_material())
	ArtUtil.cylinder(group, Vector3(axis_x, 2.55, fountain_z), 2.2, 1.3, STONE_DARK, 1.5)
	ArtUtil.cylinder(group, Vector3(axis_x, 3.8, fountain_z), 1.2, 1.2, BRONZE, 0.7)
	ArtUtil.cylinder(group, Vector3(axis_x, 5.0, fountain_z), 0.72, 2.4, BRONZE, 0.30)
	ArtUtil.sphere(group, Vector3(axis_x, 6.35, fountain_z), 0.46, BRONZE)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		var figure := ArtUtil.cylinder(group, Vector3(axis_x, 3.45, fountain_z) + direction * 5.0, 0.46, 2.3, BRONZE, 0.25)
		figure.rotation.z = 0.10 if angle < PI else -0.10
		ArtUtil.sphere(group, Vector3(axis_x, 4.75, fountain_z) + direction * 5.0, 0.28, BRONZE)
		var jet := ArtUtil.cylinder(group, Vector3(axis_x, 4.0, fountain_z) + direction * 2.1, 0.055, 3.2, Color("cfe8e8"), 0.02)
		jet.rotation.x = 0.10
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var hedge_pos := Vector3(axis_x + sin(angle) * 20.5, 0.55, fountain_z + cos(angle) * 20.5)
		var hedge := _box(group, hedge_pos, Vector3(4.0, 1.0, 1.15), Color("3f6e45"))
		hedge.rotation.y = angle
	for index in 4:
		var angle := TAU * float(index) / 4.0 + PI * 0.25
		var bed_pos := Vector3(axis_x + sin(angle) * 23.5, 0.18, fountain_z + cos(angle) * 23.5)
		_box(group, bed_pos, Vector3(5.5, 0.16, 2.2), Color("3f6e45")).rotation.y = angle
		_box(group, bed_pos + Vector3(0.0, 0.18, 0.0), Vector3(4.8, 0.12, 1.5), Color("b33e4a")).rotation.y = angle

	var fountain_label := ArtUtil.label(group, Vector3(axis_x, 8.7, fountain_z), "ARCHIBALD FOUNTAIN", 34)
	fountain_label.modulate = Color("5b4f3d")
	fountain_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	# Hyde Park Obelisk: stepped plinth and a slim tapered shaft.
	var obelisk_center := Vector3(HydeParkLayout.OBELISK.x, 0.0, HydeParkLayout.OBELISK.y)
	for step in 3:
		_box(group, obelisk_center + Vector3(0.0, 0.18 + float(step) * 0.36, 0.0), Vector3(9.0 - float(step) * 1.6, 0.36, 9.0 - float(step) * 1.6), STONE_LIGHT)
	_box(group, obelisk_center + Vector3(0.0, 1.55, 0.0), Vector3(4.2, 1.4, 4.2), STONE)
	ArtUtil.tapered_box(group, obelisk_center + Vector3(0.0, 12.8, 0.0), Vector3(2.15, 21.0, 2.15), Vector2(0.28, 0.28), STONE_LIGHT)
	ArtUtil.tapered_box(group, obelisk_center + Vector3(0.0, 23.5, 0.0), Vector3(0.55, 1.3, 0.55), Vector2(0.05, 0.05), GOLD)
	for x in [-4.1, 4.1]:
		for z in [-4.1, 4.1]:
			ArtUtil.cylinder(group, obelisk_center + Vector3(x, 0.8, z), 0.16, 1.6, METAL)

	# Anzac Memorial and the Pool of Reflection.
	var memorial := Node3D.new()
	memorial.name = "AnzacMemorial"
	group.add_child(memorial)
	var memorial_x := HydeParkLayout.MEMORIAL.x
	var memorial_z := HydeParkLayout.MEMORIAL.y
	var mc := Vector3(memorial_x, 0.0, memorial_z)
	for step in 3:
		_box(memorial, mc + Vector3(0.0, 0.14 + float(step) * 0.26, 0.0), Vector3(30.0 - float(step) * 2.2, 0.26, 23.0 - float(step) * 2.2), STONE_LIGHT.darkened(0.06))
	_box(memorial, mc + Vector3(0.0, 1.35, 0.0), Vector3(23.0, 1.5, 17.0), STONE)
	_box(memorial, mc + Vector3(0.0, 5.0, 0.0), Vector3(15.0, 6.0, 11.4), STONE_LIGHT)
	_box(memorial, mc + Vector3(0.0, 8.3, 0.0), Vector3(17.4, 0.7, 13.4), STONE_LIGHT.lightened(0.05))
	_box(memorial, mc + Vector3(0.0, 10.4, 0.0), Vector3(12.0, 3.6, 9.0), STONE)
	ArtUtil.cylinder(memorial, mc + Vector3(0.0, 13.8, 0.0), 5.4, 4.0, STONE_LIGHT, 2.5)
	ArtUtil.sphere(memorial, mc + Vector3(0.0, 16.1, 0.0), 2.7, STONE_LIGHT.lightened(0.04))
	ArtUtil.cylinder(memorial, mc + Vector3(0.0, 18.1, 0.0), 0.45, 2.6, GOLD, 0.12)
	# Flame niche and inscription.
	_box(memorial, mc + Vector3(0.0, 6.4, 5.77), Vector3(3.0, 3.0, 0.18), Color("241f1a"))
	_emissive_box(memorial, mc + Vector3(0.0, 6.3, 5.90), Vector3(1.1, 1.8, 0.10), Color("e7732e"), Color("ffb15a"), 1.8)
	var memorial_label := ArtUtil.label(memorial, mc + Vector3(0.0, 9.25, 5.75), "ANZAC MEMORIAL", 42)
	memorial_label.modulate = Color("4e4435")
	memorial_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	for x in [-9.5, 9.5]:
		_box(memorial, mc + Vector3(x, 3.0, 5.1), Vector3(1.2, 2.4, 1.2), STONE_LIGHT)
		ArtUtil.sphere(memorial, mc + Vector3(x, 4.5, 5.1), 0.55, BRONZE)
	# Pool of Reflection, on the northern (city) side of the hall.
	var pool := Vector3(HydeParkLayout.POOL.x, 0.0, HydeParkLayout.POOL.y)
	var wide := HydeParkLayout.POOL_SIZE.x
	var long := HydeParkLayout.POOL_SIZE.y
	_box(memorial, pool + Vector3(0.0, 0.10, 0.0), Vector3(wide + 3.0, 0.20, long + 3.0), STONE_LIGHT.darkened(0.10))
	_box_material(memorial, pool + Vector3(0.0, 0.22, 0.0), Vector3(wide, 0.08, long), _water_material())
	for x in [-1.0, 1.0]:
		_box(memorial, pool + Vector3(x * (wide * 0.5 + 0.35), 0.35, 0.0), Vector3(0.7, 0.6, long + 1.4), STONE)
		_box(memorial, pool + Vector3(0.0, 0.35, x * (long * 0.5 + 0.35)), Vector3(wide + 1.4, 0.6, 0.7), STONE)
	var pool_label := ArtUtil.label(memorial, pool + Vector3(0.0, 2.0, -long * 0.5 - 2.0), "LEST WE FORGET", 40)
	pool_label.modulate = Color("5a4a35")
	pool_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	# Park gates and boundary piers on the main axis.
	for gate: Vector2 in [Vector2(331.0, north_edge), Vector2(284.0, south_edge)]:
		var z := gate.y
		for x in [gate.x - 7.0, gate.x + 7.0]:
			_box(group, Vector3(x, 1.5, z), Vector3(1.5, 3.0, 1.5), STONE_LIGHT)
			ArtUtil.sphere(group, Vector3(x, 3.2, z), 0.42, STONE_LIGHT)
		var gate_label := ArtUtil.label(group, Vector3(gate.x, 4.2, z), "HYDE PARK", 56)
		gate_label.modulate = Color("d8c9aa")
		gate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _in_hyde_park(point: Vector2) -> bool:
	for ring: PackedVector2Array in _hyde_rings:
		if Geometry2D.is_point_in_polygon(point, ring):
			return true
	return false


func _paving_strip(parent: Node3D, a: Vector2, b: Vector2, width: float, height: float, color: Color) -> void:
	var delta := b - a
	if delta.length() < 0.1:
		return
	var middle := (a + b) * 0.5
	var strip := _box(parent, Vector3(middle.x, height - 0.03, middle.y),
		Vector3(width, 0.06, delta.length() + width * 0.35), color)
	strip.rotation.y = atan2(delta.x, delta.y)


func _bench(parent: Node3D, position: Vector3, yaw: float) -> void:
	var bench := Node3D.new()
	bench.position = position
	bench.rotation.y = yaw
	parent.add_child(bench)
	_box(bench, Vector3(0.0, 0.52, 0.0), Vector3(2.25, 0.14, 0.56), TIMBER)
	_box(bench, Vector3(0.0, 0.85, -0.25), Vector3(2.25, 0.55, 0.12), TIMBER)
	for x in [-0.86, 0.86]:
		_box(bench, Vector3(x, 0.27, 0.0), Vector3(0.12, 0.54, 0.48), METAL)
		_box(bench, Vector3(x, 0.61, -0.25), Vector3(0.10, 0.55, 0.10), METAL)


func _park_lamp(parent: Node3D, position: Vector3) -> void:
	ArtUtil.cylinder(parent, position + Vector3(0.0, 2.3, 0.0), 0.10, 4.6, METAL)
	_box(parent, position + Vector3(0.0, 4.66, 0.0), Vector3(0.52, 0.12, 0.52), METAL)
	_emissive_box(parent, position + Vector3(0.0, 4.94, 0.0), Vector3(0.42, 0.52, 0.42), Color("fff0c9"), Color("ffd79a"), 1.1)
	_box(parent, position + Vector3(0.0, 5.28, 0.0), Vector3(0.60, 0.12, 0.60), METAL)


func _build_circular_quay(world_data: Dictionary) -> void:
	var group := _group("CircularQuayLandmarks")
	var stops: Array = world_data.get("transit", [])
	var quay_points: Array[Vector2] = []
	var wharf_names: Array[String] = []
	for stop: Dictionary in stops:
		if str(stop.get("kind", "")) != "ferry_terminal":
			continue
		var stop_name := str(stop.get("name", ""))
		if not stop_name.begins_with("Circular Quay"):
			continue
		var point := Vector2(float(stop["x"]), float(stop["z"]))
		var duplicate := false
		for existing: Vector2 in quay_points:
			if absf(existing.x - point.x) < 20.0:
				duplicate = true
				break
		if not duplicate:
			quay_points.append(point)
			wharf_names.append(stop_name.replace("Circular Quay ", ""))
	var order := range(quay_points.size())
	order.sort_custom(func(a: int, b: int) -> bool: return quay_points[a].x < quay_points[b].x)
	var destinations := ["MANLY", "TARONGA ZOO", "WATSONS BAY", "MOSMAN", "PARRAMATTA", "DARLING HARBOUR"]
	var sorted_points: Array[Vector2] = []
	var sorted_names: Array[String] = []
	for index: int in order:
		sorted_points.append(quay_points[index])
		sorted_names.append(wharf_names[index])
	var short_names: Array[String] = []
	for x in range(quay_points.size()):
		short_names.append(wharf_names[x])

	for index in sorted_points.size():
		var point: Vector2 = sorted_points[index]
		var wharf_name: String = sorted_names[index]
		var destination: String = destinations[index % destinations.size()]
		var deck_center := Vector3(point.x, 0.85, point.y - 34.0)
		# Timber deck with a pale stone edge, piles and a green-roofed canopy.
		_box(group, deck_center, Vector3(13.0, 0.48, 76.0), TIMBER)
		_box(group, deck_center + Vector3(0.0, 0.30, 0.0), Vector3(13.4, 0.12, 76.4), STONE_LIGHT.darkened(0.05))
		for z_index in 19:
			var z := deck_center.z - 36.0 + float(z_index) * 4.0
			_box(group, Vector3(point.x, 0.98, z), Vector3(12.4, 0.04, 0.10), DARK_TIMBER)
			for side in [-1.0, 1.0]:
				ArtUtil.cylinder(group, Vector3(point.x + side * 5.8, -0.15, z), 0.30, 2.5, DARK_TIMBER)
		for side in [-1.0, 1.0]:
			_box(group, Vector3(point.x + side * 6.3, 1.15, deck_center.z), Vector3(0.16, 0.65, 76.0), METAL)
		# Waiting room and canopy.
		_box(group, Vector3(point.x, 3.9, point.y - 22.0), Vector3(9.2, 5.6, 20.0), Color("d7d7d0"))
		_box(group, Vector3(point.x, 3.9, point.y - 22.0), Vector3(9.6, 1.9, 10.0), GLASS)
		_box(group, Vector3(point.x, 6.85, point.y - 22.0), Vector3(11.0, 0.35, 24.0), COPPER)
		for z in [point.y - 33.0, point.y - 11.0]:
			for side in [-1.0, 1.0]:
				ArtUtil.cylinder(group, Vector3(point.x + side * 4.8, 3.4, z), 0.20, 6.0, METAL)
		_box(group, Vector3(point.x, 7.15, point.y - 34.0), Vector3(13.5, 0.35, 36.0), COPPER)
		for z in [point.y + 2.0, point.y - 16.0, point.y - 52.0, point.y - 69.0]:
			for side in [-1.0, 1.0]:
				ArtUtil.cylinder(group, Vector3(point.x + side * 5.6, 3.6, z), 0.14, 5.6, METAL)
		# Shore end sign: wharf number and destination.
		var sign := _facade(group, Vector3(point.x, 0.0, point.y + 2.2), Vector3.BACK, "WharfSign")
		_box(sign, Vector3(0.0, 5.5, 0.25), Vector3(7.0, 1.1, 0.26), Color("174f3c"))
		var wharf_label := ArtUtil.label(sign, Vector3(0.0, 5.5, 0.43), "WHARF " + wharf_name, 46)
		wharf_label.modulate = Color("f2e7c8")
		wharf_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		var dest_label := ArtUtil.label(sign, Vector3(0.0, 4.55, 0.30), destination, 38)
		dest_label.modulate = Color("f2e7c8")
		dest_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# Ticket machine and benches at the shore end.
		_box(group, Vector3(point.x - 4.0, 1.35, point.y - 1.0), Vector3(1.0, 2.1, 0.8), Color("223236"))
		_bench(group, Vector3(point.x + 3.8, 0.0, point.y - 4.0), PI)
		# Quay-side bollards.
		for side in [-2, 2]:
			ArtUtil.cylinder(group, Vector3(point.x + side * 8.2, 0.45, point.y - 65.0), 0.34, 0.9, Color("252b2a"), 0.24)

	# Continuous promenade behind the wharves, with paving, seats, lamps and
	# low waterfront planting.
	if not sorted_points.is_empty():
		var min_x: float = sorted_points[0].x - 18.0
		var max_x: float = sorted_points[-1].x + 24.0
		var shore_z: float = sorted_points[0].y + 12.0
		_box(group, Vector3((min_x + max_x) * 0.5, 0.12, shore_z), Vector3(max_x - min_x, 0.24, 15.0), Color("b9b2a2"))
		_box(group, Vector3((min_x + max_x) * 0.5, 0.28, shore_z - 7.2), Vector3(max_x - min_x, 0.55, 0.6), STONE)
		for index in int((max_x - min_x) / 24.0):
			var x := min_x + 12.0 + float(index) * 24.0
			_bench(group, Vector3(x, 0.0, shore_z + 4.8), PI)
			_park_lamp(group, Vector3(x + 8.0, 0.0, shore_z + 5.6))
			ArtUtil.cylinder(group, Vector3(x - 8.0, 0.45, shore_z - 6.3), 0.34, 0.9, Color("252b2a"), 0.24)
		# Quay gateway sign.
		for x in [min_x + 6.0, min_x + 26.0]:
			_box(group, Vector3(x, 3.0, shore_z + 8.0), Vector3(1.2, 6.0, 1.2), STONE_LIGHT)
		_box(group, Vector3(min_x + 16.0, 5.8, shore_z + 8.0), Vector3(22.0, 1.2, 1.3), STONE_LIGHT)
		var quay_label := ArtUtil.label(group, Vector3(min_x + 16.0, 5.8, shore_z + 8.7), "CIRCULAR QUAY", 58)
		quay_label.modulate = Color("e9dfc8")
		quay_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# Two ferries, placed in the water south of the wharves.
	if sorted_points.size() >= 2:
		_build_ferry(group, Vector3(sorted_points[0].x + 6.0, 0.40, sorted_points[0].y - 84.0), "FerryManly")
		_build_ferry(group, Vector3(sorted_points[-1].x - 8.0, 0.40, sorted_points[-1].y - 78.0), "FerryMosman")
		var bay_x := (sorted_points[0].x + sorted_points[-1].x) * 0.5
		_build_ferry(group, Vector3(bay_x, 0.40, sorted_points[0].y - 112.0), "FerryHarbourQueen")
		_build_ferry(group, Vector3(sorted_points[0].x - 42.0, 0.40, sorted_points[0].y - 52.0), "FerryCove")


func _build_ferry(parent: Node3D, center: Vector3, ferry_name: String) -> void:
	var ferry := Node3D.new()
	ferry.name = ferry_name
	parent.add_child(ferry)
	var hull := ArtUtil.tapered_box(ferry, center, Vector3(9.5, 2.0, 27.0), Vector2(7.4, 20.0), Color("315d68"))
	hull.rotation.y = PI
	_box(ferry, center + Vector3(0.0, 0.72, 0.0), Vector3(9.7, 0.45, 26.0), Color("b24a35"))
	_box(ferry, center + Vector3(0.0, 2.35, -0.5), Vector3(7.0, 2.7, 15.0), Color("e2e0d6"))
	_box(ferry, center + Vector3(0.0, 3.0, 5.8), Vector3(6.4, 1.25, 3.0), GLASS)
	_box(ferry, center + Vector3(0.0, 3.0, -6.7), Vector3(6.2, 1.2, 2.4), GLASS)
	_box(ferry, center + Vector3(0.0, 3.82, -0.5), Vector3(7.8, 0.30, 16.6), COPPER)
	_box(ferry, center + Vector3(0.0, 4.55, -1.5), Vector3(4.8, 1.5, 7.2), Color("e2e0d6"))
	_box(ferry, center + Vector3(0.0, 4.75, -1.5), Vector3(4.0, 0.8, 6.0), GLASS)
	ArtUtil.cylinder(ferry, center + Vector3(0.0, 6.2, -1.0), 0.12, 5.0, METAL)
	ArtUtil.cylinder(ferry, center + Vector3(0.0, 8.6, -1.0), 0.10, 1.8, Color("b24a35"))
	for x in [-3.2, 3.2]:
		for z in [-6.0, 0.0, 6.0]:
			_box(ferry, center + Vector3(x, 3.55, z), Vector3(0.10, 0.8, 0.10), Color("bfc4bd"))
	# Lifering and name board.
	ArtUtil.cylinder(ferry, center + Vector3(3.72, 2.4, 4.5), 0.42, 0.13, Color("d9683e"))
	var name_plate := ArtUtil.label(ferry, center + Vector3(0.0, 2.25, 7.55), "SYDNEY FERRIES", 28)
	name_plate.modulate = Color("244e42")
	name_plate.billboard = BaseMaterial3D.BILLBOARD_DISABLED


func _build_darling_harbour(world_data: Dictionary) -> void:
	var group := _group("DarlingHarbourLandmarks")
	var boardwalk_x := -622.0
	var north_z := -300.0
	var south_z := -720.0
	# Cockle Bay boardwalk along the eastern water edge.
	_box(group, Vector3(boardwalk_x, 0.30, (north_z + south_z) * 0.5), Vector3(16.0, 0.45, absf(south_z - north_z)), TIMBER)
	for z_index in 36:
		var z := north_z - float(z_index) * 11.7
		_box(group, Vector3(boardwalk_x, 0.55, z), Vector3(15.6, 0.04, 0.12), DARK_TIMBER)
	for z in range(int(north_z), int(south_z), -30):
		for x in [-9.0, 9.0]:
			ArtUtil.cylinder(group, Vector3(boardwalk_x + x, -0.1, float(z)), 0.22, 1.3, DARK_TIMBER)
		_box(group, Vector3(boardwalk_x - 8.0, 0.82, float(z)), Vector3(0.14, 1.0, 30.0), METAL)
		_bench(group, Vector3(boardwalk_x + 3.6, 0.0, float(z) - 6.0), PI * 0.5)
		_park_lamp(group, Vector3(boardwalk_x + 5.5, 0.0, float(z) - 10.0))

	# Waterfront pavilions facing the boardwalk, each with a real shopfront.
	var venue_names := ["COCKLE BAY GRILL", "HARBOUR KITCHEN", "SEA STRIFE AQUARIUM", "MADAME TWO-SODS"]
	var venue_colors := [Color("46251f"), Color("243742"), Color("0b5d8a"), Color("5a174a")]
	var venue_lettering := [Color("ffd9a0"), Color("ffcf7a"), Color("ffffff"), Color("ffd76b")]
	for index in venue_names.size():
		var z := -370.0 - float(index) * 82.0
		var pavilion := Node3D.new()
		pavilion.name = "Pavilion" + str(index)
		group.add_child(pavilion)
		_box(pavilion, Vector3(boardwalk_x + 12.0, 3.2, z), Vector3(15.0, 6.4, 24.0), Color("c7c1b3"))
		_box(pavilion, Vector3(boardwalk_x + 4.0, 4.0, z), Vector3(0.25, 4.4, 20.0), GLASS)
		_box(pavilion, Vector3(boardwalk_x + 3.7, 6.55, z), Vector3(5.0, 0.28, 25.0), Color("d9d4c6"))
		for z_side in [-9.0, 9.0]:
			ArtUtil.cylinder(pavilion, Vector3(boardwalk_x + 3.0, 2.4, z + z_side), 0.16, 4.8, METAL)
		_box(pavilion, Vector3(boardwalk_x + 3.6, 3.25, z), Vector3(0.5, 1.0, 22.0), venue_colors[index])
		var venue_label := ArtUtil.label(pavilion, Vector3(boardwalk_x + 3.28, 3.25, z), venue_names[index], 40)
		venue_label.rotation.y = -PI * 0.5
		venue_label.modulate = venue_lettering[index]
		venue_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# Awning over the boardwalk cafe frontage.
		var awning := _box(pavilion, Vector3(boardwalk_x + 0.5, 3.0, z), Vector3(4.0, 0.12, 22.0), venue_colors[index].lightened(0.18))
		awning.rotation.z = -0.16
		for bench_index in 2:
			_bench(group, Vector3(boardwalk_x + 2.0, 0.0, z - 6.0 + float(bench_index) * 12.0), -PI * 0.5)

	# Darling Harbour ferry wharf, anchored on the exported terminal point.
	var terminal := Vector3(-675.7, 0.0, -678.4)
	_box(group, terminal + Vector3(12.0, 0.75, 0.0), Vector3(44.0, 0.55, 9.0), TIMBER)
	for index in 6:
		ArtUtil.cylinder(group, terminal + Vector3(-7.0 + float(index) * 8.0, -0.05, -3.6), 0.26, 1.7, DARK_TIMBER)
		ArtUtil.cylinder(group, terminal + Vector3(-7.0 + float(index) * 8.0, -0.05, 3.6), 0.26, 1.7, DARK_TIMBER)
	_box(group, terminal + Vector3(18.0, 3.9, 0.0), Vector3(20.0, 5.8, 9.5), Color("dcd9cc"))
	_box(group, terminal + Vector3(18.0, 3.6, -4.78), Vector3(14.0, 1.5, 0.12), GLASS)
	_box(group, terminal + Vector3(18.0, 7.05, 0.0), Vector3(22.0, 0.35, 11.0), COPPER)
	var wharf_label := ArtUtil.label(group, terminal + Vector3(11.0, 5.1, -5.0), "DARLING HARBOUR WHARF 3", 38)
	wharf_label.modulate = Color("f2e7c8")
	wharf_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED

	# Cockle Bay and King Street Wharf gateways.
	for z in [north_z - 10.0, south_z + 12.0]:
		for x in [boardwalk_x - 7.0, boardwalk_x + 7.0]:
			_box(group, Vector3(x, 2.6, z), Vector3(1.1, 5.2, 1.1), STONE_LIGHT)
			ArtUtil.sphere(group, Vector3(x, 5.4, z), 0.38, STONE_LIGHT)
		var gate := ArtUtil.label(group, Vector3(boardwalk_x, 6.3, z), "COCKLE BAY WHARF", 50)
		gate.modulate = Color("e9dfc8")
		gate.billboard = BaseMaterial3D.BILLBOARD_ENABLED

	# A small marina of yachts gives the bay scale and movement without touching
	# the AI boat controller.
	for index in 3:
		_yacht(group, Vector3(-690.0 - float(index) * 14.0, 0.3, -430.0 - float(index) * 94.0), index)

	# Pyrmont Bridge follows the exported path. The road importer owns its deck;
	# this adds the truss, railings, control cabin and name board.
	var bridge_path: Array = []
	for road: Dictionary in world_data.get("roads", []):
		if String(road.get("id", "")) == "way/143655273":
			bridge_path = road.get("points", [])
			break
	if bridge_path.size() >= 2:
		_build_pyrmont_bridge(group, bridge_path)


func _yacht(parent: Node3D, center: Vector3, variant: int) -> void:
	var yacht := Node3D.new()
	yacht.name = "Yacht%d" % variant
	parent.add_child(yacht)
	var hull := ArtUtil.tapered_box(yacht, center, Vector3(3.2, 1.0, 11.0), Vector2(1.2, 8.0), Color("e4e1d5"))
	hull.rotation.y = PI * 0.5 + float(variant) * 0.2
	_box(yacht, center + Vector3(0.0, 0.7, -0.8), Vector3(1.9, 0.6, 4.0), Color("9b3d34"))
	ArtUtil.cylinder(yacht, center + Vector3(0.0, 5.4, 0.0), 0.10, 9.0, METAL)
	var sail := ArtUtil.prism(yacht, center + Vector3(0.0, 5.4, 0.0), Vector3(0.12, 7.0, 3.4), Color("e9e6d8"))
	sail.rotation.y = PI * 0.5


func _build_pyrmont_bridge(parent: Node3D, path: Array) -> void:
	var points: Array[Vector3] = []
	for point: Array in path:
		points.append(Vector3(float(point[0]), 0.2, float(point[1])))
	if points.size() < 2:
		return
	var side := Vector2(-(points[-1].z - points[0].z), points[-1].x - points[0].x).normalized()
	var lateral := Vector3(side.x, 0.0, side.y)
	for section in range(0, points.size(), 2):
		var point: Vector3 = points[section]
		for side_sign: float in [-1.0, 1.0]:
			ArtUtil.cylinder(parent, point + lateral * side_sign * 5.0 + Vector3.UP * 4.5, 0.30, 9.0, METAL)
			_box(parent, point + lateral * side_sign * 5.0 + Vector3.UP * 9.2, Vector3(0.9, 0.7, 0.9), STONE_DARK)
			_box(parent, point + lateral * side_sign * 4.9 + Vector3.UP * 1.2, Vector3(0.12, 1.2, 3.6), METAL)
	for side_sign: float in [-1.0, 1.0]:
		for section in range(0, points.size() - 1, 2):
			var a: Vector3 = points[section]
			var b: Vector3 = points[mini(section + 2, points.size() - 1)]
			var offset: Vector3 = lateral * side_sign * 5.0
			var a_low: Vector3 = a + offset + Vector3.UP * 1.1
			var b_low: Vector3 = b + offset + Vector3.UP * 1.1
			var a_high: Vector3 = a + offset + Vector3.UP * 8.5
			var b_high: Vector3 = b + offset + Vector3.UP * 8.5
			_beam(parent, a_low, b_low, 0.30, METAL)
			_beam(parent, a_high, b_high, 0.38, STONE_DARK)
			_beam(parent, a_low, b_high, 0.22, METAL)
			_beam(parent, a_high, b_low, 0.22, METAL)
			_beam(parent, a_high - offset, b_high - offset, 0.20, METAL)
	var midpoint: Vector3 = points[points.size() / 2]
	_box(parent, midpoint + Vector3.UP * 5.2, Vector3(7.0, 6.0, 6.2), Color("d8d1bf"))
	_box(parent, midpoint + Vector3.UP * 8.5, Vector3(9.0, 0.8, 8.0), COPPER)
	var label := ArtUtil.label(parent, midpoint + Vector3.UP * 7.0 + lateral * 3.3, "PYRMONT BRIDGE", 44)
	label.modulate = Color("3f3528")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED


func _beam(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var direction := b - a
	if direction.length() < 0.1:
		return
	var beam := ArtUtil.box(parent, (a + b) * 0.5, Vector3(width, width, direction.length()), color)
	var forward := direction.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var up := forward.cross(right).normalized()
	beam.basis = Basis(right, up, forward)


func _cylinder_material(parent: Node3D, position: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.bottom_radius = radius
	cylinder.top_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 24
	instance.mesh = cylinder
	instance.material_override = material
	parent.add_child(instance)
	instance.position = position
	return instance


func _box_material(parent: Node3D, position: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	instance.position = position
	return instance


func _water_material() -> StandardMaterial3D:
	if _materials.has("water"):
		return _materials["water"]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.23, 0.27, 0.88)
	material.roughness = 0.12
	material.metallic = 0.25
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials["water"] = material
	return material


func _emissive_box(parent: Node3D, position: Vector3, size: Vector3, color: Color, emission: Color, energy: float) -> MeshInstance3D:
	var key := "emissive:%s:%s:%.2f" % [color.to_html(), emission.to_html(), energy]
	var material: StandardMaterial3D
	if _materials.has(key):
		material = _materials[key]
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = energy
		_materials[key] = material
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	instance.position = position
	return instance


func _render_mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child: Node in node.get_children():
		count += _render_mesh_count(child)
	return count
