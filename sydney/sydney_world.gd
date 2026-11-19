class_name SydneyWorld
extends Node3D

## Loads the Stage A Sydney export and builds the playable world.
##
## The game keeps its own player, camera, vehicles, combat, enemies and HUD.
## This node only supplies geography, collision and spawn points. It is added
## by district.gd when `--sydney` (or SPLOOGE_SYDNEY=1) is requested, so the
## existing District Zero world and its tests remain untouched by default.

const DEFAULT_PATH := "res://sydney/world/stage_a/world.json"

## Height of the invisible shoreline barrier generated from the water polygons.
## The player's jump apex is about 1.33 m, so 2.4 m cannot be cleared.
const WATER_WALL_HEIGHT := 2.4

var data: Dictionary = {}
var player_spawn := Vector3(0.0, 0.25, 0.0)
var player_yaw := 0.0
var vehicle_spawns: Array[Vector3] = []
var vehicle_yaws: Array[float] = []
var enemy_spawn := Vector3(0.0, 0.3, -20.0)
var district_name := ""
var stats: Dictionary = {}
var pedestrian_graph: Dictionary = {}
var geometry_counts: Dictionary = {}
var build_times_ms: Dictionary = {}
var bounds: Dictionary = {}
var loaded_path := ""
var load_error := ""
var landmark_podium := PackedVector2Array()


func load_world(path: String = DEFAULT_PATH) -> bool:
	load_error = ""
	data.clear()
	if not FileAccess.file_exists(path):
		return _fail("world file not found: " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("cannot open " + path)
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return _fail("JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("root JSON value is not an object")
	data = parsed
	if String(data.get("format", "")) != "splooge-sydney-world":
		return _fail("unexpected format: " + String(data.get("format", "")))
	if int(data.get("formatVersion", 0)) != 1:
		return _fail("unsupported formatVersion: " + str(data.get("formatVersion", 0)))
	var coordinate_system: Dictionary = data.get("coordinateSystem", {})
	var scale := float(coordinate_system.get("metersPerUnit", 0.0))
	if absf(scale - 1.0) > 0.0001:
		return _fail("expected 1 metre per unit, got %s" % scale)
	bounds = data.get("bounds", {})
	if not _valid_bounds(bounds):
		return _fail("missing or invalid bounds")
	if not _read_spawns():
		return false
	var graph = data.get("pedestrianGraph", {})
	if typeof(graph) != TYPE_DICTIONARY:
		return _fail("pedestrianGraph is not an object")
	pedestrian_graph = graph
	# The landmark footprint is read before the world is built so generic
	# buildings and road ribbons that would overlap it can be suppressed.
	landmark_podium = OperaHouseLandmark.ring_from_source(OperaHouseLandmark.read_reference())
	_build()
	stats = data.get("stats", {})
	loaded_path = path
	return true


func _fail(message: String) -> bool:
	load_error = message
	push_error("SydneyWorld: " + message)
	return false


func _valid_bounds(value: Dictionary) -> bool:
	for key in ["minX", "maxX", "minZ", "maxZ"]:
		if not value.has(key) or not _finite(value[key]):
			return false
	return float(value["maxX"]) > float(value["minX"]) and float(value["maxZ"]) > float(value["minZ"])


func _read_spawns() -> bool:
	var spawn: Dictionary = data.get("spawn", {})
	var player: Dictionary = spawn.get("player", {})
	if not _point_ok(player):
		return _fail("player spawn is missing or outside bounds")
	player_spawn = Vector3(float(player["x"]), 0.25, float(player["z"]))
	player_yaw = float(player.get("yawRad", 0.0))
	district_name = str(spawn.get("district", "Sydney"))
	vehicle_spawns.clear()
	vehicle_yaws.clear()
	for item in spawn.get("vehicles", []):
		if not _point_ok(item):
			continue
		vehicle_spawns.append(Vector3(float(item["x"]), 0.2, float(item["z"])))
		vehicle_yaws.append(float(item.get("yawRad", 0.0)))
	if vehicle_spawns.is_empty():
		return _fail("no valid vehicle spawns")
	var enemy: Dictionary = spawn.get("enemy", {})
	if not _point_ok(enemy):
		return _fail("enemy spawn is missing or outside bounds")
	enemy_spawn = Vector3(float(enemy["x"]), 0.3, float(enemy["z"]))
	return true


func _point_ok(point: Dictionary) -> bool:
	if not point.has("x") or not point.has("z"):
		return false
	if not _finite(point["x"]) or not _finite(point["z"]):
		return false
	var x := float(point["x"])
	var z := float(point["z"])
	return x >= float(bounds["minX"]) - 1.0 and x <= float(bounds["maxX"]) + 1.0 \
		and z >= float(bounds["minZ"]) - 1.0 and z <= float(bounds["maxZ"]) + 1.0


func _finite(value) -> bool:
	var number := float(value)
	return not (is_nan(number) or is_inf(number))


func _build() -> void:
	var total_start := Time.get_ticks_usec()
	var start := total_start
	_build_ground()
	build_times_ms["Ground"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_water()
	build_times_ms["Water"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_water_collision()
	build_times_ms["WaterCollision"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_parks()
	build_times_ms["Parks"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_roads()
	build_times_ms["Roads"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_footpaths()
	build_times_ms["Footpaths"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_crossings()
	build_times_ms["Crossings"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_buildings()
	build_times_ms["Buildings"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_landmarks()
	build_times_ms["Landmarks"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var bridge = preload("res://sydney/landmarks/harbour_bridge.gd").new()
	bridge.name = "HarbourBridge"
	bridge.build()
	add_child(bridge)
	geometry_counts["HarbourBridge"] = bridge.stats
	build_times_ms["HarbourBridge"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_harbour_water()
	build_times_ms["HarbourWater"] = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["Total"] = (Time.get_ticks_usec() - total_start) / 1000.0


func _build_ground() -> void:
	var min_x := float(bounds["minX"])
	var max_x := float(bounds["maxX"])
	var min_z := float(bounds["minZ"])
	var max_z := float(bounds["maxZ"])
	var size := Vector3(max_x - min_x + 300.0, 1.0, max_z - min_z + 300.0)
	var center := Vector3((min_x + max_x) * 0.5, -0.5, (min_z + max_z) * 0.5)
	var instance := MeshInstance3D.new()
	instance.name = "Ground"
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.material_override = SydneyMesh.mat(Color("5d6258"))
	instance.position = center
	add_child(instance)
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = center
	body.add_child(collider)


func _build_water() -> void:
	var water = data.get("water", null)
	if typeof(water) != TYPE_DICTIONARY:
		return
	var rings: Array = water.get("rings", [])
	var mesh := SydneyMesh.flat_polygons(rings, 0.02, Color("2b6f86"))
	_add_mesh("Water", mesh)


## Phase 6A harbour water step. The harbour module (sydney/harbour/) owns the
## visual harbour water for the whole southern harbour, the preserved ponds,
## the land collar beyond the ground box, and a shoreline barrier built with
## the Phase 4 mechanism. When its data is present it supersedes the Stage A
## "Water" mesh and "WaterCollision" body (they share a plane, so both would
## z-fight); when its data is missing this step does nothing and the Stage A
## water above remains the whole harbour. This is the only integration point.
func _build_harbour_water() -> void:
	var harbour = preload("res://sydney/harbour/harbour_water.gd").new()
	harbour.name = "HarbourWater"
	if harbour.build():
		add_child(harbour)
		geometry_counts["HarbourWater"] = harbour.stats
	else:
		var reason := String(harbour.build_error)
		harbour.free()
		push_warning("SydneyWorld: harbour water skipped: " + reason)


## The harbour is visual-only in Stage A, so the shoreline is bounded by a
## single invisible wall built from the same rings that are rendered as water.
## One edge -> two vertical triangles, all in one body: the barrier sits exactly
## on the visible coast (no guessed rectangles), follows every inlet, and cannot
## block land that is outside the water polygons.
func _build_water_collision() -> void:
	var water = data.get("water", null)
	if typeof(water) != TYPE_DICTIONARY:
		push_warning("SydneyWorld: no water data; the harbour has no collision")
		return
	var rings: Array = water.get("rings", [])
	var faces := PackedVector3Array()
	var edges := 0
	for ring in rings:
		var points: Array = ring
		if points.size() < 3:
			continue
		for index in points.size():
			var a := Vector2(float(points[index][0]), float(points[index][1]))
			var next: Array = points[(index + 1) % points.size()]
			var b := Vector2(float(next[0]), float(next[1]))
			if a.distance_squared_to(b) < 0.0025:
				continue
			var bottom_a := Vector3(a.x, 0.0, a.y)
			var bottom_b := Vector3(b.x, 0.0, b.y)
			var top_a := Vector3(a.x, WATER_WALL_HEIGHT, a.y)
			var top_b := Vector3(b.x, WATER_WALL_HEIGHT, b.y)
			faces.append(bottom_a)
			faces.append(bottom_b)
			faces.append(top_b)
			faces.append(bottom_a)
			faces.append(top_b)
			faces.append(top_a)
			edges += 1
	if faces.is_empty():
		push_warning("SydneyWorld: no usable water rings; the harbour has no collision")
		return
	var body := StaticBody3D.new()
	body.name = "WaterCollision"
	add_child(body)
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	# Rings are wound per source polygon, so collide from both sides.
	shape.backface_collision = true
	shape.set_faces(faces)
	collider.shape = shape
	body.add_child(collider)
	geometry_counts["WaterCollision"] = {
		"rings": rings.size(),
		"edges": edges,
		"triangles": faces.size() / 3,
		"heightM": WATER_WALL_HEIGHT,
	}


func _build_parks() -> void:
	var rings: Array = []
	for park in data.get("parks", []):
		for ring in park.get("rings", []):
			rings.append(ring)
	var mesh := SydneyMesh.flat_polygons(rings, 0.04, Color("5f8f52"))
	_add_mesh("Parks", mesh)


func _build_roads() -> void:
	# Tunnels remain in the data for lanes/navigation, but drawing their 2D
	# ribbon on the surface would put a motorway through buildings.
	# Roads that run under the Opera House podium are split there rather than
	# drawn through the landmark shell.
	var roads: Array = OperaHouseLandmark.filtered_roads(data.get("roads", []), landmark_podium)
	var mesh := SydneyMesh.road_mesh(roads, data.get("junctions", []), 0.06, Color("30353a"))
	_add_mesh("Roads", mesh)


func _build_footpaths() -> void:
	var paths: Array = []
	var widths: Array = []
	for footpath in data.get("footpaths", []):
		var path: Array = []
		for point in footpath.get("points", []):
			path.append(Vector2(float(point[0]), float(point[1])))
		if path.size() < 2:
			continue
		paths.append(path)
		widths.append(float(footpath.get("widthM", 2.0)))
	var mesh := SydneyMesh.flat_paths(paths, widths, 0.10, Color("bbb6a6"))
	_add_mesh("Footpaths", mesh)


func _build_crossings() -> void:
	# The exporter puts every derived crossing at the junction centre. Four such
	# markings at one intersection would stack into a radial target pattern, so
	# shift only the paint along each road approach. The crossing centre in the
	# data and the walkable footpath are unchanged.
	var roads: Dictionary = {}
	for road in data.get("roads", []):
		roads[str(road.get("id", ""))] = road
	var rows: Array = []
	for source in data.get("crossings", []):
		var row: Dictionary = source.duplicate(true)
		var angle := float(row.get("angleRad", 0.0))
		var road: Dictionary = roads.get(str(row.get("roadId", "")), {})
		var width := float(road.get("widthM", 8.0))
		var along_road := Vector2(-sin(angle), cos(angle))
		var shift := width * 0.5 + 2.0
		row["x"] = float(row.get("x", 0.0)) + along_road.x * shift
		row["z"] = float(row.get("z", 0.0)) + along_road.y * shift
		var x := float(row["x"])
		var z := float(row["z"])
		if x < float(bounds.get("minX", -INF)) or x > float(bounds.get("maxX", INF)) \
			or z < float(bounds.get("minZ", -INF)) or z > float(bounds.get("maxZ", INF)):
			continue
		rows.append(row)
	var mesh := SydneyMesh.crossings(rows, 0.12, Color("e9e4d2"))
	_add_mesh("Crossings", mesh)


func _build_landmarks() -> void:
	var reference := OperaHouseLandmark.read_reference()
	if reference.is_empty():
		push_warning("SydneyWorld: Opera House reference missing; landmark skipped")
		return
	var landmark := OperaHouseLandmark.new()
	landmark.name = "OperaHouse"
	if not landmark.build(reference):
		push_warning("SydneyWorld: Opera House landmark failed: " + landmark.build_error)
		landmark.free()
		return
	add_child(landmark)
	geometry_counts["OperaHouse"] = landmark.stats


func _build_buildings() -> void:
	var assemblable: Array = OperaHouseLandmark.filtered_buildings(data.get("buildings", []), landmark_podium)
	var assembler_script = preload("res://sydney/architecture/assembler.gd")
	var assembler = assembler_script.new()
	var selected: Array = assembler_script.pilot(assemblable, player_spawn)
	var architecture: Node3D = assembler.assemble(selected)
	add_child(architecture)
	geometry_counts["Architecture"] = {"converted": selected.size(), "fallback": assemblable.size() - selected.size(), "buildings": architecture.get_meta("buildings")}
	var built := SydneyMesh.buildings(assemblable)
	var mesh = built.get("mesh")
	if mesh != null:
		_add_mesh("Buildings", SydneyMesh.engine_building_mesh(mesh))
	var faces: PackedVector3Array = built.get("faces", PackedVector3Array())
	geometry_counts["Buildings"] = {
		"vertices": geometry_counts.get("Buildings", {}).get("vertices", 0),
		"triangles": geometry_counts.get("Buildings", {}).get("triangles", 0),
		"collisionTriangles": faces.size() / 3,
		"built": int(built.get("built", 0)),
		"skipped": int(built.get("skipped", 0)),
		"degenerateTriangles": int(built.get("degenerateTriangles", 0)),
	}
	if int(built.get("skipped", 0)) > 0:
		push_warning("SydneyWorld: skipped %d malformed/empty building footprints" % int(built.get("skipped", 0)))
	if faces.size() >= 3:
		var body := StaticBody3D.new()
		body.name = "BuildingCollision"
		add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(SydneyMesh.engine_building_faces(faces))
		collider.shape = shape
		body.add_child(collider)


func _add_mesh(node_name: String, mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	var vertices := 0
	var triangles := 0
	for surface_index in mesh.get_surface_count():
		vertices += mesh.surface_get_array_len(surface_index)
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and indices.size() > 0:
			triangles += indices.size() / 3
		else:
			triangles += mesh.surface_get_array_len(surface_index) / 3
	geometry_counts[node_name] = {"vertices": vertices, "triangles": triangles}
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)
