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
var _world_text_hash: int = 0

static var _portal_meshes: Dictionary = {}
## Bump when _build_buildings()'s geometry/collision output changes shape,
## so stale caches from an older build never get loaded silently.
const BUILDING_CACHE_VERSION := 1
## Bump when _build_roads()'s cached mesh output changes shape.
const ROAD_CACHE_VERSION := 1
const TUNNEL_Y := -9.0


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
	_world_text_hash = text.hash()
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


func _roads_cache_path() -> String:
	return "user://cache/roads_v%d_%d.res" % [ROAD_CACHE_VERSION, _world_text_hash]


func _load_roads_cache() -> RoadMeshCacheData:
	var path := _roads_cache_path()
	if not ResourceLoader.exists(path):
		return null
	var cache := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if cache is RoadMeshCacheData:
		return cache
	return null


func _save_roads_cache(cache: RoadMeshCacheData) -> void:
	if OS.has_feature("web"):
		return  # browser storage cannot hold the caches
	DirAccess.make_dir_recursive_absolute("user://cache")
	var err := ResourceSaver.save(cache, _roads_cache_path())
	if err != OK:
		push_warning("SydneyWorld: failed to write roads cache (error %d)" % err)


## The surface ribbon and both tunnel meshes are deterministic for a given
## export file and take ~5 s of SurfaceTool work across the whole road
## network (docs/PERFORMANCE_AUDIT_2026-11-24.md §10), so they're cached the
## same way _build_buildings() caches its mesh. Tunnel portal frames are cheap
## node-tree construction, built fresh every run below.
func _build_roads() -> void:
	# Surface roads are drawn as ribbons; tunnel-tagged roads are rendered as
	# authored 3D tunnel structures below ground instead of being omitted.
	# Roads that run under the Opera House podium are split there rather than
	# drawn through the landmark shell.
	var roads: Array = OperaHouseLandmark.filtered_roads(data.get("roads", []), landmark_podium)

	var cache := _load_roads_cache()
	if cache == null:
		var mesh := SydneyMesh.road_mesh(roads, data.get("junctions", []), 0.06, Color("30353a"))
		var surface_mesh := SydneyMesh.tunnel_road_surface_mesh(roads, TUNNEL_Y, Color("2a2e33"))
		var shell_mesh := SydneyMesh.tunnel_road_shell_mesh(roads, TUNNEL_Y, Color("4a4d52"))
		cache = RoadMeshCacheData.new()
		cache.roads_mesh = mesh
		var roads_counted := _count_mesh(mesh) if mesh != null else {"vertices": 0, "triangles": 0}
		cache.roads_vertices = int(roads_counted["vertices"])
		cache.roads_triangles = int(roads_counted["triangles"])
		cache.tunnel_surface_mesh = surface_mesh
		var surface_counted := _count_mesh(surface_mesh) if surface_mesh != null else {"vertices": 0, "triangles": 0}
		cache.tunnel_surface_vertices = int(surface_counted["vertices"])
		cache.tunnel_surface_triangles = int(surface_counted["triangles"])
		cache.tunnel_shell_mesh = shell_mesh
		var shell_counted := _count_mesh(shell_mesh) if shell_mesh != null else {"vertices": 0, "triangles": 0}
		cache.tunnel_shell_vertices = int(shell_counted["vertices"])
		cache.tunnel_shell_triangles = int(shell_counted["triangles"])
		_save_roads_cache(cache)

	if cache.roads_mesh != null:
		_add_cached_mesh("Roads", cache.roads_mesh, cache.roads_vertices, cache.roads_triangles)
	if cache.tunnel_surface_mesh != null:
		_add_cached_mesh("RoadTunnels", cache.tunnel_surface_mesh, cache.tunnel_surface_vertices, cache.tunnel_surface_triangles)
	if cache.tunnel_shell_mesh != null:
		_add_cached_mesh("RoadTunnelShells", cache.tunnel_shell_mesh, cache.tunnel_shell_vertices, cache.tunnel_shell_triangles)
	_build_road_tunnel_portals(roads)


func _build_road_tunnel_portals(roads: Array) -> void:
	# Simple portal frames at true tunnel mouths (endpoints that are not shared
	# with another tunnel segment) for visible transitions.
	var tunnel_roads: Array = []
	for road in roads:
		if bool(road.get("tunnel", false)):
			tunnel_roads.append(road)
	if tunnel_roads.is_empty():
		return

	var endpoint_counts: Dictionary = {}
	for road in tunnel_roads:
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		for endpoint_index in [0, points.size() - 1]:
			var p: Array = points[endpoint_index]
			var key := "%d,%d" % [int(round(float(p[0]))), int(round(float(p[1])))]
			endpoint_counts[key] = int(endpoint_counts.get(key, 0)) + 1

	var portals := Node3D.new()
	portals.name = "RoadTunnelPortals"
	add_child(portals)
	var built := 0
	var seen: Dictionary = {}
	for road in tunnel_roads:
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var width: float = maxf(float(road.get("widthM", 8.0)), 4.0)
		for endpoint_index in [0, points.size() - 1]:
			var p: Array = points[endpoint_index]
			var key := "%d,%d" % [int(round(float(p[0]))), int(round(float(p[1])))]
			if int(endpoint_counts.get(key, 0)) != 1:
				continue
			if seen.has(key):
				continue
			seen[key] = true
			var other_index := 1 if endpoint_index == 0 else points.size() - 2
			var a: Array = points[endpoint_index]
			var b: Array = points[other_index]
			var dir := Vector2(float(a[0]) - float(b[0]), float(a[1]) - float(b[1]))
			if dir.length() < 0.01:
				continue
			dir = dir.normalized()
			var yaw := atan2(-dir.x, -dir.y)
			var portal := Node3D.new()
			portal.position = Vector3(float(a[0]), TUNNEL_Y, float(a[1]))
			portal.rotation.y = yaw
			portals.add_child(portal)
			var opening_w: float = width + 2.2
			var opening_h: float = 5.6
			# Frame around tunnel mouth.
			_add_portal_box(portal, Vector3(-(opening_w * 0.5 + 0.5), opening_h * 0.5, 0.0), Vector3(1.0, opening_h + 1.0, 1.2), Color("6b6962"))
			_add_portal_box(portal, Vector3(opening_w * 0.5 + 0.5, opening_h * 0.5, 0.0), Vector3(1.0, opening_h + 1.0, 1.2), Color("6b6962"))
			_add_portal_box(portal, Vector3(0.0, opening_h + 0.5, 0.0), Vector3(opening_w + 2.0, 1.0, 1.2), Color("747168"))
			_add_portal_box(portal, Vector3(0.0, -0.2, 0.0), Vector3(opening_w + 1.4, 0.4, 1.4), Color("3a3d42"))
			built += 1

	var tunnel_counts: Dictionary = geometry_counts.get("RoadTunnels", {})
	geometry_counts["RoadTunnels"] = {
		"roads": tunnel_roads.size(),
		"vertices": int(tunnel_counts.get("vertices", 0)),
		"triangles": int(tunnel_counts.get("triangles", 0)),
		"portals": built,
		"depthY": TUNNEL_Y,
	}
	var shell_counts: Dictionary = geometry_counts.get("RoadTunnelShells", {})
	geometry_counts["RoadTunnelShells"] = {
		"vertices": int(shell_counts.get("vertices", 0)),
		"triangles": int(shell_counts.get("triangles", 0)),
		"depthY": TUNNEL_Y,
	}


func _add_portal_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var key := "box:%s:%s:%s" % [size.x, size.y, size.z]
	var box: BoxMesh = _portal_meshes.get(key)
	if box == null:
		box = BoxMesh.new()
		box.size = size
		_portal_meshes[key] = box
	mesh_instance.mesh = box
	mesh_instance.material_override = SydneyMesh.mat(color)
	mesh_instance.position = pos
	parent.add_child(mesh_instance)


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


func _buildings_cache_path() -> String:
	return "user://cache/buildings_v%d_%d.res" % [BUILDING_CACHE_VERSION, _world_text_hash]


func _load_buildings_cache() -> BuildingMeshCacheData:
	var path := _buildings_cache_path()
	if not ResourceLoader.exists(path):
		return null
	var cache := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if cache is BuildingMeshCacheData:
		return cache
	return null


func _save_buildings_cache(cache: BuildingMeshCacheData) -> void:
	if OS.has_feature("web"):
		return  # browser storage cannot hold the caches
	DirAccess.make_dir_recursive_absolute("user://cache")
	var err := ResourceSaver.save(cache, _buildings_cache_path())
	if err != OK:
		push_warning("SydneyWorld: failed to write buildings cache (error %d)" % err)


## Merging ~19k building footprints into one mesh + collision shape is
## ~16 s of pure GDScript geometry math and fully deterministic for a given
## export file, so the result is cached to disk on first build and reused on
## every later launch of the same city data (see docs/PERFORMANCE_AUDIT_2026-11-24.md §8/§9).
func _build_buildings() -> void:
	var assemblable: Array = OperaHouseLandmark.filtered_buildings(data.get("buildings", []), landmark_podium)
	var assembler_script = preload("res://sydney/architecture/assembler.gd")
	var assembler = assembler_script.new()
	var selected: Array = assembler_script.pilot(assemblable, player_spawn)
	var architecture: Node3D = assembler.assemble(selected)
	add_child(architecture)
	geometry_counts["Architecture"] = {"converted": selected.size(), "fallback": assemblable.size() - selected.size(), "buildings": architecture.get_meta("buildings")}

	var cache := _load_buildings_cache()
	if cache == null:
		var built := SydneyMesh.buildings(assemblable)
		var raw_mesh = built.get("mesh")
		var engine_mesh: Mesh = SydneyMesh.engine_building_mesh(raw_mesh) if raw_mesh != null else null
		var faces: PackedVector3Array = built.get("faces", PackedVector3Array())
		var shape: Shape3D = null
		if faces.size() >= 3:
			var concave := ConcavePolygonShape3D.new()
			concave.set_faces(SydneyMesh.engine_building_faces(faces))
			shape = concave
		var vertices := 0
		if engine_mesh != null:
			for surface_index in engine_mesh.get_surface_count():
				vertices += engine_mesh.surface_get_array_len(surface_index)
		cache = BuildingMeshCacheData.new()
		cache.mesh = engine_mesh
		cache.shape = shape
		cache.collision_triangles = faces.size() / 3
		cache.built = int(built.get("built", 0))
		cache.skipped = int(built.get("skipped", 0))
		cache.degenerate_triangles = int(built.get("degenerateTriangles", 0))
		cache.vertices = vertices
		cache.triangles = faces.size() / 3
		_save_buildings_cache(cache)

	if cache.mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = "Buildings"
		instance.mesh = cache.mesh
		add_child(instance)
	geometry_counts["Buildings"] = {
		"vertices": cache.vertices,
		"triangles": cache.triangles,
		"collisionTriangles": cache.collision_triangles,
		"built": cache.built,
		"skipped": cache.skipped,
		"degenerateTriangles": cache.degenerate_triangles,
	}
	if cache.skipped > 0:
		push_warning("SydneyWorld: skipped %d malformed/empty building footprints" % cache.skipped)
	if cache.shape != null:
		var body := StaticBody3D.new()
		body.name = "BuildingCollision"
		add_child(body)
		var collider := CollisionShape3D.new()
		collider.shape = cache.shape
		body.add_child(collider)


func _add_mesh(node_name: String, mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	var counted := _count_mesh(mesh)
	_add_cached_mesh(node_name, mesh, int(counted["vertices"]), int(counted["triangles"]))


func _count_mesh(mesh: Mesh) -> Dictionary:
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
	return {"vertices": vertices, "triangles": triangles}


## Like _add_mesh(), but takes pre-known vertex/triangle counts instead of
## recomputing them by fetching every surface's full array — the counting
## path a cache hit should skip along with the mesh generation itself.
func _add_cached_mesh(node_name: String, mesh: Mesh, vertices: int, triangles: int) -> void:
	geometry_counts[node_name] = {"vertices": vertices, "triangles": triangles}
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	add_child(instance)
