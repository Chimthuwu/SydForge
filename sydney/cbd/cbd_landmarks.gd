extends Node3D

## Low-poly, authored identity details for the expanded Sydney world.
##
## The Stage B export owns the real street/building footprints and parks. This
## module adds only the silhouettes those footprints cannot provide: clock
## towers, cathedral spires, park monuments, ferry wharves, and the Pyrmont
## Bridge truss. All coordinates use the installed Sydney metre projection.

const ArtUtil := preload("res://scripts/art.gd")
const SydneyMeshBuilder := preload("res://sydney/sydney_mesh.gd")
const CbdCivic := preload("res://sydney/cbd/cbd_civic.gd")
const TOWER_ANCHOR_ID := "way/389002928"

const STONE := Color("cdbb9c")
const STONE_LIGHT := Color("e0d2b7")
const STONE_DARK := Color("96866e")
const ROOF_GREEN := Color("536d61")
const ROOF_SLATE := Color("45545a")
const BRICK := Color("9d5e47")
const WINDOW := Color("334a55")
const GOLD := Color("c9a75b")
const WATER := Color("4b9eae")
const METAL := Color("4c5a5b")

var stats: Dictionary = {}


func build(world_data: Dictionary) -> void:
	name = "SydneyCBDLandmarks"
	_build_queen_victoria_building(world_data)
	_build_st_marys_cathedral(world_data)
	_build_central_station(world_data)
	_build_sydney_tower(world_data)
	_build_st_andrews_cathedral(world_data)
	_build_general_post_office(world_data)
	var civic := CbdCivic.new()
	civic.name = "SydneyCivicLandmarks"
	civic.build(world_data)
	add_child(civic)
	_batch_recursive(self)
	var tower_present := false
	if not _building_row(world_data, TOWER_ANCHOR_ID).is_empty():
		tower_present = true
	stats = {
		"sydneyTower": tower_present,
		"queenVictoriaBuilding": true,
		"townHall": true,
		"stMarysCathedral": true,
		"hydePark": true,
		"centralStation": true,
		"circularQuayWharves": civic.stats.get("circularQuayWharves", 0),
		"darlingHarbourWharves": civic.stats.get("darlingHarbourWharves", 0),
		"pyrmontBridge": true,
		"osmBuildingMasses": 3,
		"renderMeshNodes": _render_mesh_count(self),
		"civicDetailMeshes": civic.stats.get("renderMeshNodes", 0),
	}


func _group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	add_child(group)
	return group


func _building_row(world_data: Dictionary, wanted_id: String) -> Dictionary:
	for row: Dictionary in world_data.get("buildings", []):
		if String(row.get("id", "")) == wanted_id:
			return row
	return {}


func _ring_center(row: Dictionary) -> Vector2:
	var ring: Array = row.get("ring", [])
	var center := Vector2.ZERO
	for point: Array in ring:
		center += Vector2(float(point[0]), float(point[1]))
	return center / maxf(1.0, float(ring.size()))


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


func _add_osm_mass(parent: Node3D, row: Dictionary, tint: Color) -> void:
	# Preserve the exact OSM footprint and walk-blocking collision while replacing
	# the generic striped facade with an authored stone silhouette.
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


func _add_clock_face(parent: Node3D, center: Vector3, radius: float, direction: String) -> void:
	var normal := Vector3.FORWARD
	if direction == "front":
		normal = Vector3.BACK
	elif direction == "back":
		normal = Vector3.FORWARD
	elif direction == "right":
		normal = Vector3.RIGHT
	else:
		normal = Vector3.LEFT

	var disk := ArtUtil.cylinder(parent, center, radius, 0.28, Color("3e4240"))
	var face_center := center + normal * 0.20
	var face := ArtUtil.cylinder(parent, face_center, radius * 0.82, 0.14, STONE_LIGHT)
	var hand_center := face_center + normal * 0.09
	var vertical_hand_size := Vector3(0.14, radius * 1.05, 0.10)
	var horizontal_hand_size := Vector3(radius * 0.65, 0.14, 0.10)
	match direction:
		"front":
			disk.rotation.x = PI * 0.5
			face.rotation.x = PI * 0.5
		"back":
			disk.rotation.x = -PI * 0.5
			face.rotation.x = -PI * 0.5
		"right":
			disk.rotation.z = -PI * 0.5
			face.rotation.z = -PI * 0.5
			vertical_hand_size = Vector3(0.08, radius * 1.1, 0.10)
			horizontal_hand_size = Vector3(0.08, 0.10, radius * 0.62)
		_:
			disk.rotation.z = PI * 0.5
			face.rotation.z = PI * 0.5
			vertical_hand_size = Vector3(0.08, radius * 1.1, 0.10)
			horizontal_hand_size = Vector3(0.08, 0.10, radius * 0.62)
	var hand_long := ArtUtil.box(parent, hand_center, vertical_hand_size, ROOF_SLATE)
	var hand_short := ArtUtil.box(parent, hand_center, horizontal_hand_size, ROOF_SLATE)
	hand_short.position.y -= radius * 0.13


func _clock_tower(
	parent: Node3D,
	center: Vector2,
	base_y: float,
	width: float,
	shaft_height: float,
	stone: Color,
	roof: Color,
) -> void:
	var tower_center := Vector3(center.x, base_y + shaft_height * 0.5, center.y)
	ArtUtil.box(parent, tower_center, Vector3(width, shaft_height, width), stone)
	var clock_y := base_y + shaft_height * 0.72
	var offset := width * 0.5 + 0.15
	var clock_radius := maxf(width * 0.28, 2.8)
	_add_clock_face(parent, Vector3(center.x, clock_y, center.y + offset), clock_radius, "front")
	_add_clock_face(parent, Vector3(center.x, clock_y, center.y - offset), clock_radius, "back")
	_add_clock_face(parent, Vector3(center.x + offset, clock_y, center.y), clock_radius, "right")
	_add_clock_face(parent, Vector3(center.x - offset, clock_y, center.y), clock_radius, "left")

	var cap_y := base_y + shaft_height + 1.5
	ArtUtil.box(parent, Vector3(center.x, cap_y, center.y), Vector3(width + 2.0, 2.0, width + 2.0), stone.lightened(0.12))
	ArtUtil.cylinder(parent, Vector3(center.x, cap_y + 4.2, center.y), width * 0.48, 6.5, roof, width * 0.08)
	ArtUtil.cylinder(parent, Vector3(center.x, cap_y + 9.6, center.y), 0.85, 5.0, GOLD, 0.05)


func _build_queen_victoria_building(world_data: Dictionary) -> void:
	var row := _building_row(world_data, "way/40717424")
	if row.is_empty():
		return
	var group := _group("QueenVictoriaBuilding")
	var bounds := _ring_bounds(row)
	var center := _ring_center(row)
	var height := float(row.get("heightM", 13.0))
	var west := bounds.position.x
	var east := bounds.end.x
	var north := bounds.position.y
	var south := bounds.end.y
	_add_osm_mass(group, row, Color("cdbc9e"))

	# Arcaded masonry rhythm along the long George/Pitt Street sides.
	for index in 12:
		var z := lerpf(north + 10.0, south - 10.0, float(index) / 11.0)
		for side in [-1.0, 1.0]:
			var x: float = center.x + side * (bounds.size.x * 0.5 + 0.45)
			ArtUtil.box(group, Vector3(x, height * 0.48, z), Vector3(0.85, height * 0.92, 1.0), STONE_LIGHT)
	for level in [3.5, 7.7, 11.1]:
		for index in 10:
			var z := lerpf(north + 17.0, south - 17.0, float(index) / 9.0)
			for side in [-1.0, 1.0]:
				var x: float = center.x + side * (bounds.size.x * 0.5 + 0.53)
				ArtUtil.box(group, Vector3(x, level, z), Vector3(0.10, 2.6, 3.2), WINDOW)
	for side in [-1.0, 1.0]:
		var x: float = center.x + side * (bounds.size.x * 0.5 + 0.6)
		ArtUtil.box(group, Vector3(x, height + 0.25, center.y), Vector3(1.4, 0.65, bounds.size.y - 4.0), STONE_LIGHT)

	# The dominant green copper dome and its smaller corner cupolas establish
	# the QVB silhouette above the retained OSM footprint.
	ArtUtil.cylinder(group, Vector3(center.x, height + 2.8, center.y), 10.5, 5.2, STONE_LIGHT)
	var dome := ArtUtil.sphere(group, Vector3(center.x, height + 12.5, center.y), 12.5, ROOF_GREEN)
	dome.scale = Vector3(1.0, 0.82, 1.0)
	ArtUtil.cylinder(group, Vector3(center.x, height + 22.0, center.y), 4.2, 5.0, STONE_LIGHT)
	_add_clock_face(group, Vector3(center.x, height + 22.0, center.y + 4.35), 1.7, "front")
	ArtUtil.cylinder(group, Vector3(center.x, height + 26.0, center.y), 3.2, 4.5, ROOF_GREEN, 1.5)
	ArtUtil.cylinder(group, Vector3(center.x, height + 30.5, center.y), 0.9, 6.0, GOLD, 0.04)
	for x in [west + 4.0, east - 4.0]:
		for z in [north + 8.0, south - 8.0]:
			ArtUtil.cylinder(group, Vector3(x, height + 2.7, z), 2.2, 5.4, STONE_LIGHT, 1.5)
			ArtUtil.cylinder(group, Vector3(x, height + 6.0, z), 1.6, 3.0, ROOF_GREEN, 0.05)


func _build_town_hall(world_data: Dictionary) -> void:
	var row := _building_row(world_data, "way/104948253")
	if row.is_empty():
		return
	var group := _group("SydneyTownHall")
	var bounds := _ring_bounds(row)
	var center := _ring_center(row)
	var height := float(row.get("heightM", 13.0))
	_add_osm_mass(group, row, Color("c3ad8e"))

	# Classical sandstone entrance colonnade on the long southern frontage.
	for index in 9:
		var x := lerpf(bounds.position.x + 8.0, bounds.end.x - 8.0, float(index) / 8.0)
		ArtUtil.box(group, Vector3(x, height * 0.48, bounds.end.y + 0.7), Vector3(1.1, height * 0.92, 0.8), STONE_LIGHT)
		ArtUtil.box(group, Vector3(x, height + 0.15, bounds.end.y + 0.7), Vector3(2.4, 0.7, 1.25), STONE_LIGHT)
		ArtUtil.box(group, Vector3(x, height * 0.52, bounds.position.y - 0.7), Vector3(1.1, height * 0.92, 0.8), STONE_LIGHT)

	var tower_center := Vector2(center.x, center.y)
	_clock_tower(group, tower_center, height, 12.0, 30.0, STONE_LIGHT, ROOF_GREEN)
	for x_offset in [-bounds.size.x * 0.3, bounds.size.x * 0.3]:
		var dome_center := Vector3(center.x + x_offset, height + 3.5, center.y)
		var dome := ArtUtil.sphere(group, dome_center, 4.0, ROOF_GREEN)
		dome.scale = Vector3(1.0, 0.7, 1.0)
		ArtUtil.cylinder(group, dome_center + Vector3.UP * 3.3, 1.2, 2.0, GOLD, 0.08)


func _build_st_marys_cathedral(world_data: Dictionary) -> void:
	var row := _building_row(world_data, "way/16749128")
	if row.is_empty():
		return
	var group := _group("StMarysCathedral")
	var bounds := _ring_bounds(row)
	var height := float(row.get("heightM", 26.0))
	var center := _ring_center(row)
	var nave_z := center.y
	_add_osm_mass(group, row, Color("b9aa92"))

	# Long slate gable over the nave, with paired Gothic tower-and-spire masses
	# on the western forecourt front.
	var roof_left := ArtUtil.box(group, Vector3(center.x - 8.5, height + 5.0, nave_z), Vector3(20.0, 0.9, bounds.size.y - 12.0), ROOF_SLATE)
	roof_left.rotation.z = 0.42
	var roof_right := ArtUtil.box(group, Vector3(center.x + 8.5, height + 5.0, nave_z), Vector3(20.0, 0.9, bounds.size.y - 12.0), ROOF_SLATE)
	roof_right.rotation.z = -0.42
	ArtUtil.box(group, Vector3(center.x, height + 9.0, nave_z), Vector3(2.0, 1.0, bounds.size.y - 12.0), ROOF_SLATE)

	for z in [bounds.position.y + 18.0, bounds.end.y - 18.0]:
		var tower := Vector2(bounds.position.x + 7.0, z)
		ArtUtil.box(group, Vector3(tower.x, height + 17.0, tower.y), Vector3(9.0, 34.0, 9.0), STONE_LIGHT)
		ArtUtil.box(group, Vector3(tower.x, height + 34.5, tower.y), Vector3(11.0, 1.2, 11.0), STONE)
		ArtUtil.cylinder(group, Vector3(tower.x, height + 43.0, tower.y), 4.2, 16.0, ROOF_SLATE, 0.08)
		ArtUtil.cylinder(group, Vector3(tower.x, height + 53.5, tower.y), 0.65, 6.0, GOLD, 0.03)
		ArtUtil.box(group, Vector3(tower.x - 4.65, height + 15.0, tower.y), Vector3(0.16, 7.0, 1.8), WINDOW)
		ArtUtil.box(group, Vector3(tower.x - 4.65, height + 25.0, tower.y), Vector3(0.16, 6.0, 1.8), WINDOW)
		for z_side in [-1.0, 1.0]:
			ArtUtil.box(group, Vector3(tower.x + 4.8, height + 7.0, tower.y + z_side * 5.0), Vector3(2.5, 13.0, 2.0), STONE)
	var rose_window := ArtUtil.cylinder(
		group, Vector3(bounds.position.x - 0.45, height * 0.72, center.y),
		4.2, 0.22, ROOF_SLATE
	)
	rose_window.rotation.z = -PI * 0.5
	var rose_trim := ArtUtil.cylinder(
		group, Vector3(bounds.position.x - 0.6, height * 0.72, center.y), 2.9, 0.24, STONE_LIGHT, 2.6
	)
	rose_trim.rotation.z = -PI * 0.5

	# Buttresses and narrow lancet windows read as Gothic masonry at street level.
	for index in 6:
		var z := lerpf(bounds.position.y + 14.0, bounds.end.y - 14.0, float(index) / 5.0)
		for side in [-1.0, 1.0]:
			var x: float = center.x + side * (bounds.size.x * 0.44)
			var buttress := ArtUtil.tapered_box(
				group, Vector3(x, 12.0, z), Vector3(4.0, 23.0, 4.5),
				Vector2(1.3, 2.0), STONE_LIGHT
			)
			buttress.rotation.z = -side * 0.12
			ArtUtil.box(group, Vector3(x + side * 2.2, 15.5, z), Vector3(0.18, 7.0, 1.3), WINDOW)


## St Andrew's Cathedral — the twin-spire Gothic silhouette directly beside
## the Town Hall menu spawn, previously just the generic striped shell. The
## nave runs east-west with the twin spires and rose window on the George
## Street (west) front, as built.
func _build_st_andrews_cathedral(world_data: Dictionary) -> void:
	var row := _building_row(world_data, "way/104948254")
	if row.is_empty():
		return
	var group := _group("StAndrewsCathedral")
	var bounds := _ring_bounds(row)
	var height := float(row.get("heightM", 30.0))
	var center := _ring_center(row)
	_add_osm_mass(group, row, Color("c7b79b"))

	# Slate gable over the nave, running east-west (slope across z, unlike
	# St Mary's north-south nave).
	var nave_length := bounds.size.x - 10.0
	var roof_north := ArtUtil.box(group, Vector3(center.x, height + 4.6, center.y - 8.5), Vector3(nave_length, 0.9, 18.0), ROOF_SLATE)
	roof_north.rotation.x = 0.42
	var roof_south := ArtUtil.box(group, Vector3(center.x, height + 4.6, center.y + 8.5), Vector3(nave_length, 0.9, 18.0), ROOF_SLATE)
	roof_south.rotation.x = -0.42
	ArtUtil.box(group, Vector3(center.x, height + 8.4, center.y), Vector3(nave_length, 0.9, 1.8), ROOF_SLATE)

	# Twin pinnacled towers flanking the west front (the real cathedral's
	# George Street face), rising from the roof line like St Mary's pair.
	for z_tower in [center.y - 12.0, center.y + 12.0]:
		var tower_x := bounds.position.x + 5.5
		ArtUtil.box(group, Vector3(tower_x, height + 14.0, z_tower), Vector3(8.0, 28.0, 8.0), STONE_LIGHT)
		ArtUtil.box(group, Vector3(tower_x, height + 28.5, z_tower), Vector3(10.0, 1.1, 10.0), STONE)
		ArtUtil.cylinder(group, Vector3(tower_x, height + 35.0, z_tower), 3.6, 13.0, ROOF_SLATE, 0.08)
		ArtUtil.cylinder(group, Vector3(tower_x, height + 43.5, z_tower), 0.5, 5.0, GOLD, 0.03)
		for z_side in [-1.0, 1.0]:
			ArtUtil.box(group, Vector3(tower_x, height + 8.0, z_tower + z_side * 4.4), Vector3(2.2, 12.0, 1.8), STONE)

	# Rose window and a gold finial cross on the west front.
	var rose_window := ArtUtil.cylinder(
		group, Vector3(bounds.position.x - 0.45, height * 0.72, center.y),
		3.4, 0.22, ROOF_SLATE
	)
	rose_window.rotation.z = -PI * 0.5
	var rose_trim := ArtUtil.cylinder(
		group, Vector3(bounds.position.x - 0.6, height * 0.72, center.y), 2.3, 0.24, STONE_LIGHT, 2.1
	)
	rose_trim.rotation.z = -PI * 0.5
	ArtUtil.cylinder(group, Vector3(bounds.end.x + 0.4, height + 10.4, center.y), 0.28, 2.2, GOLD, 0.05)

	# Buttresses and lancets along both long (north/south) faces.
	for index in 5:
		var x := lerpf(bounds.position.x + 14.0, bounds.end.x - 10.0, float(index) / 4.0)
		for side in [-1.0, 1.0]:
			var z_buttress: float = center.y + side * (bounds.size.y * 0.44)
			var buttress := ArtUtil.tapered_box(
				group, Vector3(x, 11.5, z_buttress), Vector3(4.5, 22.0, 4.0),
				Vector2(2.0, 1.3), STONE_LIGHT
			)
			buttress.rotation.x = side * 0.12
			ArtUtil.box(group, Vector3(x, 15.0, z_buttress + side * 2.1), Vector3(1.3, 6.5, 0.18), WINDOW)


## The Sydney General Post Office — the Martin Place spawn's missing
## landmark. The mapped footprint keeps the real 97 m arcade block; this adds
## the long sandstone colonnade along the Martin Place (north) face and the
## clock tower campanile at its western end. No OSM tower anchor exists, so
## the campanile's corner placement is an authored call (DECISION 9459065).
func _build_general_post_office(world_data: Dictionary) -> void:
	var row := _building_row(world_data, "way/282238525")
	if row.is_empty():
		return
	var group := _group("GeneralPostOffice")
	var height := float(row.get("heightM", 16.0))
	_add_osm_mass(group, row, Color("d3c6ae"))

	# The mapped ring is rotated ~6 degrees to the world grid, so the
	# colonnade must follow the ring's actual northernmost edge - an
	# axis-aligned colonnade floats up to 10 m off the face at the east end.
	var ring: Array = row.get("ring", [])
	if ring.size() < 3:
		return
	var north_a := Vector2.ZERO
	var north_b := Vector2.ZERO
	var best_z := INF
	for index in ring.size():
		var point := Vector2(float(ring[index][0]), float(ring[index][1]))
		var next_point := Vector2(float(ring[(index + 1) % ring.size()][0]), float(ring[(index + 1) % ring.size()][1]))
		var mid_z := (point.y + next_point.y) * 0.5
		if mid_z < best_z:
			best_z = mid_z
			north_a = point
			north_b = next_point
	if north_a.x > north_b.x:
		var swap := north_a
		north_a = north_b
		north_b = swap
	var edge_dir := (north_b - north_a).normalized()
	var edge_yaw := atan2(-edge_dir.y, edge_dir.x)
	var centroid := Vector2.ZERO
	for point: Array in ring:
		centroid += Vector2(float(point[0]), float(point[1]))
	centroid /= float(ring.size())
	var outward := Vector2(edge_dir.y, -edge_dir.x)
	if outward.dot(north_a - centroid) < 0.0:
		outward = -outward

	# Classical colonnade along the Martin Place frontage with capitals and a
	# full-length entablature, 1 m proud of the mapped face.
	for index in 14:
		var along := north_a + edge_dir * lerpf(6.0, (north_b - north_a).length() - 6.0, float(index) / 13.0) + outward * 1.0
		ArtUtil.box(group, Vector3(along.x, height * 0.42, along.y), Vector3(1.0, height * 0.84, 1.0), STONE_LIGHT)
		ArtUtil.box(group, Vector3(along.x, height * 0.84 + 0.25, along.y), Vector3(2.3, 0.5, 2.3), STONE_LIGHT)
	var entablature := ArtUtil.box(
		group,
		Vector3((north_a.x + north_b.x) * 0.5 + outward.x * 1.0, height * 0.92, (north_a.y + north_b.y) * 0.5 + outward.y * 1.0),
		Vector3((north_b - north_a).length() - 4.0, 0.9, 1.6), STONE_LIGHT
	)
	entablature.rotation.y = edge_yaw

	# The campanile: square shaft with four clock faces, cornice cap, tapered
	# copper pyramid and gold finial, rising from the building's west end.
	var campanile := north_a + edge_dir * 8.0 - outward * 2.0
	_clock_tower(group, campanile, height, 9.0, 34.0, STONE_LIGHT, ROOF_SLATE)


func _build_central_station(world_data: Dictionary) -> void:
	var group := _group("CentralStationLandmark")
	var clock := Vector2(-187.6, 1034.1)
	# 2026-11-29: the shell was trimmed from 100 m to 80 m wide (west edge
	# x -224 -> -204) because the mapped 'Station Pickup/Dropoff' road
	# (way/784391848) and generated building gen/central/463/0 rendered
	# straight through the west wing. The box collision below keeps the
	# landmark solid like the other authored landmarks (QVB/Town Hall/St
	# Mary's), which previously let the player and cars walk through it.
	var half_width := 40.0
	var station := Vector3(-164.0, 0.0, 1050.0)

	# A sandstone grand-concourse frontage and the unmistakable Central clock
	# tower. The station export has transit locations but no complete building
	# shell, so the OSM clocktower point anchors the authored silhouette.
	ArtUtil.box(group, station + Vector3(0.0, 8.0, 0.0), Vector3(80.0, 16.0, 30.0), Color("b89b77"))
	ArtUtil.box(group, station + Vector3(0.0, 16.5, 0.0), Vector3(88.0, 1.0, 34.0), STONE_LIGHT)
	for index in 8:
		var x := station.x - 35.0 + float(index) * 10.0
		ArtUtil.box(group, Vector3(x, 7.0, station.z + 15.8), Vector3(1.1, 13.0, 1.1), STONE_LIGHT)
		ArtUtil.box(group, Vector3(x, 8.0, station.z + 16.45), Vector3(4.2, 5.0, 0.25), WINDOW)
		ArtUtil.box(group, Vector3(x, 7.0, station.z - 15.8), Vector3(1.1, 13.0, 1.1), STONE_LIGHT)
		ArtUtil.box(group, Vector3(x, 8.0, station.z - 16.45), Vector3(4.2, 5.0, 0.25), WINDOW)
	var west_face := station.x - half_width - 0.8
	for index in 9:
		var z := station.z - 13.0 + float(index) * 3.25
		ArtUtil.box(group, Vector3(west_face, 7.0, z), Vector3(0.9, 14.0, 1.0), STONE_LIGHT)
		ArtUtil.box(group, Vector3(west_face - 0.48, 8.0, z), Vector3(0.15, 6.2, 1.9), WINDOW)
	ArtUtil.box(group, Vector3(west_face - 0.15, 15.8, station.z), Vector3(0.9, 1.2, 30.0), STONE_LIGHT)
	var station_sign := ArtUtil.label(group, Vector3(west_face - 0.8, 20.5, station.z), "CENTRAL", 84)
	station_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# The east face is what the 'central' menu spawn looks at across Eddy
	# Avenue; it used to be a blank wall while the sign faced the pickup road.
	var east_face := station.x + half_width + 0.8
	for index in 9:
		var z_east := station.z - 13.0 + float(index) * 3.25
		ArtUtil.box(group, Vector3(east_face, 7.0, z_east), Vector3(0.9, 14.0, 1.0), STONE_LIGHT)
		ArtUtil.box(group, Vector3(east_face + 0.48, 8.0, z_east), Vector3(0.15, 6.2, 1.9), WINDOW)
	ArtUtil.box(group, Vector3(east_face + 0.15, 15.8, station.z), Vector3(0.9, 1.2, 30.0), STONE_LIGHT)
	var east_sign := ArtUtil.label(group, Vector3(east_face + 0.8, 20.5, station.z), "CENTRAL", 84)
	east_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Grand-entry read on the Eddy Avenue (north) frontage: sandstone steps and
	# a recessed entry portal. Presentation only (outside the collision box).
	for step in 3:
		ArtUtil.box(
			group,
			Vector3(station.x, 0.14 + float(step) * 0.22, station.z - 17.2 + float(step) * 0.55),
			Vector3(14.0 - float(step) * 1.2, 0.22, 1.1), STONE_LIGHT
		)
	ArtUtil.box(group, Vector3(station.x, 2.3, station.z - 15.35), Vector3(8.0, 4.6, 0.5), Color("241f1a"))
	ArtUtil.box(group, Vector3(station.x, 4.9, station.z - 15.5), Vector3(9.4, 0.7, 0.9), STONE_LIGHT)
	# The tower rises through the building from the forecourt, so its shaft
	# starts at the ground (the old base_y 17 left the north half of the
	# 14 m-wide tower hanging 17 m above Eddy Avenue with a visible void).
	_clock_tower(group, clock, 0.0, 14.0, 67.0, STONE_LIGHT, ROOF_GREEN)

	# Solid collision for the frontage and the clock tower shaft (the roof
	# canopies behind stay walk/drive-under, as they really are).
	var body := StaticBody3D.new()
	body.name = "CentralStationCollision"
	group.add_child(body)
	var shell := CollisionShape3D.new()
	var shell_box := BoxShape3D.new()
	shell_box.size = Vector3(80.0, 17.0, 30.0)
	shell.shape = shell_box
	shell.position = station + Vector3(0.0, 8.5, 0.0)
	body.add_child(shell)
	var tower := CollisionShape3D.new()
	var tower_box := BoxShape3D.new()
	tower_box.size = Vector3(14.0, 67.0, 14.0)
	tower.shape = tower_box
	tower.position = Vector3(clock.x, 33.5, clock.y)
	body.add_child(tower)

	# Platform yard south of the concourse: four platform slabs with their
	# iron canopies, five track wells between them and two static K-set style
	# carriages parked at the platforms (the same presentation pattern as the
	# static ferries at Circular Quay). The old canopy columns hung 4 m above
	# empty ground with nothing under the roofs.
	var platform_z_center := 1180.0
	var platform_length := 190.0
	for platform in 4:
		var x := -142.0 + float(platform) * 18.0
		# Concrete platform slab and its yellow tactile edge strips.
		ArtUtil.box(group, Vector3(x, 0.55, platform_z_center), Vector3(11.0, 1.1, platform_length), Color("8e887c"))
		for edge in [-1.0, 1.0]:
			ArtUtil.box(group, Vector3(x + edge * 5.1, 1.12, platform_z_center), Vector3(0.7, 0.16, platform_length), Color("c8b23c"))
		for section in 6:
			var z := 1100.0 + float(section) * 32.0
			ArtUtil.box(group, Vector3(x, 6.15, z), Vector3(0.65, 11.7, 0.65), METAL)
			ArtUtil.box(group, Vector3(x, 12.2, z), Vector3(12.0, 0.55, 30.0), ROOF_SLATE)
			ArtUtil.box(group, Vector3(x, 13.0, z), Vector3(0.35, 0.4, 29.0), STONE_LIGHT)
	for well in 5:
		var track_x := -151.0 + float(well) * 18.0
		ArtUtil.box(group, Vector3(track_x, 0.05, platform_z_center), Vector3(4.6, 0.2, platform_length), Color("3d3b38"))
		for rail in [-1.0, 1.0]:
			ArtUtil.box(group, Vector3(track_x + rail * 0.7175, 0.19, platform_z_center), Vector3(0.14, 0.18, platform_length), Color("90999c"))
	for train_x in [-133.0, -97.0]:
		for carriage_index in 3:
			var carriage_z := 1180.0 - float(carriage_index) * 19.8
			_build_carriage(group, Vector3(train_x, 0.0, carriage_z))
	ArtUtil.box(group, station + Vector3(0.0, 20.0, 16.0), Vector3(38.0, 4.0, 0.55), ROOF_GREEN)
	ArtUtil.label(group, station + Vector3(0.0, 20.0, 16.35), "CENTRAL", 48)


## A parked double-deck suburban carriage (Sydney K-set read: silver body,
## twin dark window bands, orange-red door panels) on the given track centre.
func _build_carriage(parent: Node3D, at: Vector3) -> void:
	var carriage := Node3D.new()
	carriage.name = "CentralCarriage"
	carriage.position = at
	parent.add_child(carriage)
	var body_color := Color("b9bec4")
	var roof_color := Color("6d7278")
	var glass_color := Color("22282e")
	var door_color := Color("c94f38")
	ArtUtil.box(carriage, Vector3(0.0, 2.2, 0.0), Vector3(3.05, 3.5, 19.0), body_color)
	ArtUtil.box(carriage, Vector3(0.0, 4.17, 0.0), Vector3(2.85, 0.35, 19.0), roof_color)
	for side in [-1.0, 1.0]:
		ArtUtil.box(carriage, Vector3(side * 1.53, 1.35, 0.0), Vector3(0.12, 1.15, 16.5), glass_color)
		ArtUtil.box(carriage, Vector3(side * 1.53, 2.85, 0.0), Vector3(0.12, 1.15, 16.5), glass_color)
		for door in [-1.0, 0.0, 1.0]:
			ArtUtil.box(carriage, Vector3(side * 1.54, 1.7, float(door) * 6.2), Vector3(0.14, 2.6, 1.15), door_color)
	ArtUtil.box(carriage, Vector3(0.0, 2.0, -9.55), Vector3(2.9, 3.1, 0.3), Color("565b60"))
	ArtUtil.box(carriage, Vector3(0.0, 2.0, 9.55), Vector3(2.9, 3.1, 0.3), Color("565b60"))


## Sydney Tower Eye — the CBD's tallest spire and its most recognisable
## silhouette, previously absent. The shaft rises from the mapped Centrepoint
## block (TOWER_ANCHOR_ID, the tallest building on its real Market/Elizabeth
## block) so the tower is anchored to data, not a guessed position. Proportions
## follow the real structure scaled to this world: observation pod at ~230 m,
## golden turret, cab and the 1 MHz antenna mast to ~270 m.
func _build_sydney_tower(world_data: Dictionary) -> void:
	var row := _building_row(world_data, TOWER_ANCHOR_ID)
	if row.is_empty():
		push_warning("CBDLandmarks: Sydney Tower anchor building missing; tower skipped")
		return
	var group := _group("SydneyTowerLandmark")
	var center := _ring_center(row)
	var base := float(row.get("heightM", 44.0))
	var shaft := Vector3(center.x, base, center.y)
	var shaft_height := 170.0
	# Slim concrete shaft (the real tower's 1 m-thick core reads as a needle).
	ArtUtil.cylinder(group, shaft + Vector3(0.0, shaft_height * 0.5, 0.0), 3.4, shaft_height, Color("b9b4a8"))
	# Podium ring and the golden observation turret.
	var pod_y := base + shaft_height + 12.0
	ArtUtil.cylinder(group, Vector3(center.x, base + shaft_height, center.y), 8.0, 2.4, STONE_LIGHT)
	ArtUtil.cylinder(group, Vector3(center.x, pod_y, center.y), 13.0, 22.0, GOLD)
	# Cabin band with dark glazing, and the upper maintenance level.
	ArtUtil.cylinder(group, Vector3(center.x, pod_y + 8.0, center.y), 13.4, 5.0, WINDOW)
	ArtUtil.cylinder(group, Vector3(center.x, pod_y + 15.5, center.y), 10.0, 4.0, STONE_LIGHT)
	# Antenna mast with the red tip beacon, to ~270 m.
	ArtUtil.cylinder(group, Vector3(center.x, pod_y + 17.5 + 18.0, center.y), 1.1, 36.0, METAL)
	ArtUtil.cylinder(group, Vector3(center.x, pod_y + 17.5 + 37.5, center.y), 0.45, 3.0, Color("d94f43"))
	# Solid collision: shaft and turret only (the mast stays decorative).
	var body := StaticBody3D.new()
	body.name = "SydneyTowerCollision"
	group.add_child(body)
	var shaft_collider := CollisionShape3D.new()
	var shaft_box := BoxShape3D.new()
	shaft_box.size = Vector3(9.0, shaft_height + 34.0, 9.0)
	shaft_collider.shape = shaft_box
	shaft_collider.position = Vector3(center.x, base + (shaft_height + 34.0) * 0.5, center.y)
	body.add_child(shaft_collider)


func _build_circular_quay(world_data: Dictionary) -> void:
	var group := _group("CircularQuayLandmarks")
	var stops: Array = world_data.get("transit", [])
	var quay_points: Array[Vector2] = []
	for stop: Dictionary in stops:
		if str(stop.get("kind", "")) != "ferry_terminal":
			continue
		if not str(stop.get("name", "")).begins_with("Circular Quay"):
			continue
		var point := Vector2(float(stop["x"]), float(stop["z"]))
		var duplicate := false
		for existing: Vector2 in quay_points:
			if absf(existing.x - point.x) < 22.0:
				duplicate = true
				break
		if not duplicate:
			quay_points.append(point)
	quay_points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	for index in quay_points.size():
		var point: Vector2 = quay_points[index]
		var x := point.x
		var z := point.y - 22.0
		ArtUtil.box(group, Vector3(x, 0.5, z), Vector3(8.0, 0.8, 68.0), STONE_DARK)
		ArtUtil.box(group, Vector3(x, 1.08, point.y - 42.0), Vector3(10.0, 0.25, 22.0), STONE_LIGHT)
		ArtUtil.box(group, Vector3(x, 4.2, point.y + 10.0), Vector3(9.0, 6.5, 18.0), WINDOW)
		ArtUtil.box(group, Vector3(x, 7.55, point.y + 10.0), Vector3(13.0, 0.55, 21.0), STONE_LIGHT)
		for side in [-1.0, 1.0]:
			ArtUtil.box(group, Vector3(x + side * 4.4, 1.0, z), Vector3(0.22, 1.4, 68.0), METAL)

	# Two static low-poly ferries make the terminal geometry legible without
	# adding any moving traffic or changing the traffic agent's ownership.
	if not quay_points.is_empty():
		var first: Vector2 = quay_points[mini(2, quay_points.size() - 1)]
		var last: Vector2 = quay_points[-1]
		_build_ferry(group, Vector3(first.x, 0.65, first.y - 82.0), "CircularQuayFerry")
		_build_ferry(group, Vector3(last.x, 0.65, last.y - 82.0), "CircularQuayFerryEast")
		ArtUtil.label(group, Vector3(first.x, 10.0, first.y + 20.0), "CIRCULAR QUAY", 28)


func _build_darling_harbour(world_data: Dictionary) -> void:
	var group := _group("DarlingHarbourLandmarks")
	# The data contains actual Pyrmont Bridge path geometry. The road mesh already
	# supplies its deck, so this adds only the historic rail/truss silhouette.
	var bridge_path: Array = []
	for road: Dictionary in world_data.get("roads", []):
		if String(road.get("id", "")) == "way/143655273":
			bridge_path = road.get("points", [])
			break
	if bridge_path.size() >= 2:
		_build_pyrmont_bridge_truss(group, bridge_path)

	# Piers use the exported Darling Harbour ferry terminals as their anchors.
	var stops: Array = world_data.get("transit", [])
	var wharf_points: Array[Vector2] = []
	for stop: Dictionary in stops:
		if str(stop.get("kind", "")) != "ferry_terminal":
			continue
		var terminal_name := str(stop.get("name", ""))
		if terminal_name.contains("Darling Harbour") or terminal_name.contains("Pyrmont Bay"):
			wharf_points.append(Vector2(float(stop["x"]), float(stop["z"])))
	wharf_points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for index in mini(wharf_points.size(), 4):
		var point: Vector2 = wharf_points[index]
		# Wharf pontoons sit on the east and west banks of Cockle Bay, extending
		# out from their mapped ferry-terminal point.
		var east_bank := point.x > -700.0
		var direction := -1.0 if east_bank else 1.0
		var center := Vector3(point.x + direction * 22.0, 0.45, point.y)
		ArtUtil.box(group, center, Vector3(48.0, 0.7, 8.0), STONE_DARK)
		ArtUtil.box(group, center + Vector3(direction * 15.0, 2.8, 0.0), Vector3(14.0, 5.0, 10.0), WINDOW)
		ArtUtil.box(group, center + Vector3(direction * 15.0, 5.45, 0.0), Vector3(17.0, 0.55, 13.0), STONE_LIGHT)
	_build_ferry(group, Vector3(-650.0, 0.65, -574.0), "DarlingHarbourFerry")
	ArtUtil.label(group, Vector3(-602.0, 12.0, -398.0), "DARLING HARBOUR", 26)


func _build_ferry(parent: Node3D, center: Vector3, node_name: String) -> void:
	var ferry := Node3D.new()
	ferry.name = node_name
	parent.add_child(ferry)
	var hull := ArtUtil.tapered_box(
		ferry, center, Vector3(10.0, 1.8, 25.0), Vector2(7.0, 19.0), Color("334e59")
	)
	hull.rotation.y = PI
	ArtUtil.box(ferry, center + Vector3(0.0, 2.2, 0.0), Vector3(6.6, 2.8, 11.0), STONE_LIGHT)
	ArtUtil.box(ferry, center + Vector3(0.0, 3.65, -0.3), Vector3(5.6, 1.3, 7.0), WINDOW)
	ArtUtil.box(ferry, center + Vector3(0.0, 4.35, -0.3), Vector3(7.0, 0.3, 8.0), Color("b94d3d"))


func _build_pyrmont_bridge_truss(parent: Node3D, path: Array) -> void:
	var points: Array[Vector3] = []
	for point: Array in path:
		points.append(Vector3(float(point[0]), 0.2, float(point[1])))
	var side: Vector2 = Vector2(-(points[-1].z - points[0].z), points[-1].x - points[0].x).normalized()
	for section in range(0, points.size(), 2):
		var point: Vector3 = points[section]
		for side_sign in [-1.0, 1.0]:
			var lateral: Vector3 = Vector3(side.x, 0.0, side.y) * side_sign * 4.6
			ArtUtil.box(parent, point + lateral + Vector3.UP * 7.0, Vector3(0.55, 13.5, 0.55), METAL)
	if points.size() < 2:
		return
	for side_sign in [-1.0, 1.0]:
		for section in range(0, points.size() - 1, 2):
			var a := points[section]
			var b := points[mini(section + 2, points.size() - 1)]
			var lateral: Vector3 = Vector3(side.x, 0.0, side.y) * side_sign * 4.6
			var a_low := a + lateral + Vector3.UP * 2.0
			var b_low := b + lateral + Vector3.UP * 2.0
			var a_high := a + lateral + Vector3.UP * 13.0
			var b_high := b + lateral + Vector3.UP * 13.0
			_beam_between(parent, a_low, b_low, 0.55, METAL)
			_beam_between(parent, a_high, b_high, 0.65, STONE_DARK)
			_beam_between(parent, a_low, b_high, 0.38, METAL)
			_beam_between(parent, a_high, b_low, 0.38, METAL)

	var midpoint: Vector3 = points[points.size() / 2]
	ArtUtil.box(parent, midpoint + Vector3.UP * 5.0, Vector3(8.0, 7.0, 7.0), STONE_LIGHT)
	ArtUtil.box(parent, midpoint + Vector3.UP * 9.0, Vector3(10.0, 1.0, 9.0), ROOF_GREEN)


func _beam_between(parent: Node3D, a: Vector3, b: Vector3, width: float, tint: Color) -> void:
	var direction := b - a
	var beam := ArtUtil.box(parent, (a + b) * 0.5, Vector3(width, width, direction.length()), tint)
	var forward := direction.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var up := forward.cross(right).normalized()
	beam.basis = Basis(right, up, forward)


func _batch_recursive(node: Node) -> void:
	var children := node.get_children()
	for child: Node in children:
		if child.get_child_count() > 0:
			_batch_recursive(child)
	if node is Node3D:
		_batch_mesh_children(node as Node3D)


func _batch_mesh_children(parent: Node3D) -> void:
	var batches: Dictionary = {}
	for child: Node in parent.get_children():
		if not child is MeshInstance3D or child.get_child_count() > 0:
			continue
		var instance := child as MeshInstance3D
		if instance.mesh == null or instance.material_override == null:
			continue
		var material: Material = instance.material_override
		var key := material.get_instance_id()
		if not batches.has(key):
			batches[key] = {"material": material, "instances": []}
		var entries: Array = batches[key]["instances"]
		entries.append(instance)
	for key in batches:
		var batch: Dictionary = batches[key]
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var instances: Array = batch["instances"]
		for instance: MeshInstance3D in instances:
			for surface_index in instance.mesh.get_surface_count():
				surface.append_from(instance.mesh, surface_index, instance.transform)
		var combined := surface.commit()
		if combined == null or combined.get_surface_count() == 0:
			continue
		combined.surface_set_material(0, batch["material"])
		var merged := MeshInstance3D.new()
		merged.name = "LandmarkBatch_%s" % str(key)
		merged.mesh = combined
		parent.add_child(merged)
		for instance: MeshInstance3D in instances:
			parent.remove_child(instance)
			instance.free()


func _render_mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child: Node in node.get_children():
		count += _render_mesh_count(child)
	return count
