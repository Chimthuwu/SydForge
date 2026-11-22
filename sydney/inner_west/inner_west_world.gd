class_name InnerWestWorld
extends Node3D

## Loads the Inner West district export (Phase 6C) and builds the playable
## district: terrain-aware streets, footpaths, steps, crossings, rail
## corridors, neighbourhood-styled buildings, parks, harbour water with a
## shoreline barrier, bridge decks with barriers, an authored Anzac Bridge, and
## street trees.
##
## This node is intentionally a sibling of the Stage A `SydneyWorld`, not a
## modification of it: the CBD, Opera House and Harbour Bridge stay exactly as
## Phase 3–5 built them. Both worlds share the same origin, projection and
## axis convention, and the Inner West terrain blends to 0 at the Stage A seam,
## so the districts tile seamlessly.


const DEFAULT_PATH := "res://sydney/world/inner_west/world.json"
const WATER_Y := -0.38
const VIADUCT_LIFT := 5.0
const RAIL_LIFT := 6.0

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
var height_grid: Dictionary = {}
var loaded_path := ""
var load_error := ""
var neighbourhood_names: Dictionary = {}


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
	if json.parse(text) != OK:
		return _fail("JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("root JSON value is not an object")
	data = parsed
	if String(data.get("format", "")) != "splooge-sydney-world":
		return _fail("unexpected format: " + String(data.get("format", "")))
	if int(data.get("formatVersion", 0)) != 1:
		return _fail("unsupported formatVersion: " + str(data.get("formatVersion", 0)))
	if String(data.get("districtId", "")) != "inner_west":
		return _fail("unexpected districtId: " + String(data.get("districtId", "")))
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
	stats = data.get("stats", {})
	loaded_path = path
	_load_height_grid()
	_build()
	return true


func _fail(message: String) -> bool:
	load_error = message
	push_error("InnerWestWorld: " + message)
	return false


func _valid_bounds(value: Dictionary) -> bool:
	for key in ["minX", "maxX", "minZ", "maxZ"]:
		if not value.has(key) or not _finite(value[key]):
			return false
	return float(value["maxX"]) > float(value["minX"]) and float(value["maxZ"]) > float(value["minZ"])


func _finite(value) -> bool:
	var number := float(value)
	return not (is_nan(number) or is_inf(number))


func _point_ok(point: Dictionary) -> bool:
	if not point.has("x") or not point.has("z"):
		return false
	if not _finite(point["x"]) or not _finite(point["z"]):
		return false
	var x := float(point["x"])
	var z := float(point["z"])
	return x >= float(bounds["minX"]) - 2.0 and x <= float(bounds["maxX"]) + 2.0 \
		and z >= float(bounds["minZ"]) - 2.0 and z <= float(bounds["maxZ"]) + 2.0


func _read_spawns() -> bool:
	var spawn: Dictionary = data.get("spawn", {})
	var player: Dictionary = spawn.get("player", {})
	if not _point_ok(player):
		return _fail("player spawn is missing or outside bounds")
	player_spawn = Vector3(float(player["x"]), 2.0, float(player["z"]))
	player_yaw = float(player.get("yawRad", 0.0))
	district_name = str(spawn.get("district", "Inner West"))
	vehicle_spawns.clear()
	vehicle_yaws.clear()
	for item in spawn.get("vehicles", []):
		if not _point_ok(item):
			continue
		vehicle_spawns.append(Vector3(float(item["x"]), 2.0, float(item["z"])))
		vehicle_yaws.append(float(item.get("yawRad", 0.0)))
	if vehicle_spawns.is_empty():
		return _fail("no valid vehicle spawns")
	var enemy: Dictionary = spawn.get("enemy", {})
	if not _point_ok(enemy):
		return _fail("enemy spawn is missing or outside bounds")
	enemy_spawn = Vector3(float(enemy["x"]), 2.0, float(enemy["z"]))
	return true


func _load_height_grid() -> void:
	var terrain: Dictionary = data.get("terrain", {})
	if terrain.is_empty():
		push_warning("InnerWestWorld: no terrain block; the district will be flat")
		height_grid = {
			"data": PackedFloat32Array(), "nx": 2, "nz": 2,
			"minX": float(bounds["minX"]), "minZ": float(bounds["minZ"]),
			"spacing": maxf(float(bounds["maxX"]) - float(bounds["minX"]), 1.0),
			"hMin": 0.0, "hMax": 0.0,
		}
		return
	var bin_path := loaded_path.get_base_dir().path_join(String(terrain.get("file", "height.bin")))
	var raw := InnerWestMesh.load_height_grid(bin_path)
	if raw.is_empty():
		push_warning("InnerWestWorld: height grid failed to load; using flat grid")
		height_grid = {
			"data": PackedFloat32Array(), "nx": 2, "nz": 2,
			"minX": float(bounds["minX"]), "minZ": float(bounds["minZ"]),
			"spacing": maxf(float(bounds["maxX"]) - float(bounds["minX"]), 1.0),
			"hMin": 0.0, "hMax": 0.0,
		}
		return
	height_grid = InnerWestMesh.grid_from_meta(raw["data"], terrain)
	for item in data.get("neighbourhoods", []):
		neighbourhood_names[String(item.get("id", ""))] = String(item.get("name", ""))


# ------------------------------------------------------------------ build --
func _build() -> void:
	var total_start := Time.get_ticks_usec()
	var start := total_start
	_build_terrain()
	build_times_ms["Terrain"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_water()
	build_times_ms["Water"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_parks()
	build_times_ms["Parks"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_roads_and_rail()
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
	_build_trees()
	build_times_ms["Trees"] = (Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	_build_landmarks()
	build_times_ms["Landmarks"] = (Time.get_ticks_usec() - start) / 1000.0
	build_times_ms["Total"] = (Time.get_ticks_usec() - total_start) / 1000.0


func _build_terrain() -> void:
	var built := InnerWestMesh.terrain_mesh(height_grid, 8)
	if built["mesh"] != null:
		_add_mesh("Terrain", built["mesh"])
	_add_chunk_bodies("TerrainCollision", built["chunkFaces"], false)


func _build_water() -> void:
	var water = data.get("water", null)
	if typeof(water) != TYPE_DICTIONARY:
		push_warning("InnerWestWorld: no water data; bays have no surface")
		return
	var rings: Array = water.get("rings", [])
	var mesh := InnerWestMesh.flat_polygons(rings, WATER_Y, Color("2b6f86"))
	_add_mesh("Water", mesh)
	var shore: Array = water.get("shoreRings", [])
	if not shore.is_empty():
		_add_mesh("ShoreBand", InnerWestMesh.flat_polygons(shore, WATER_Y + 0.045, Color("4c8ea3")))
	# shoreline barrier
	var faces := InnerWestMesh.shore_faces(height_grid, rings, -2.0, 2.4)
	if faces.size() >= 3:
		var body := StaticBody3D.new()
		body.name = "WaterCollision"
		add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		collider.shape = shape
		body.add_child(collider)
		geometry_counts["WaterCollision"] = {"rings": rings.size(), "triangles": faces.size() / 3}


func _build_parks() -> void:
	var park_rings: Array = []
	var pitch_rings: Array = []
	for park in data.get("parks", []):
		var kind := String(park.get("kind", ""))
		var target := pitch_rings if kind in ["pitch", "track", "golf_course", "playground"] else park_rings
		for ring in park.get("rings", []):
			target.append(ring)
	if not park_rings.is_empty():
		_add_mesh("Parks", InnerWestMesh.draped_polygons(height_grid, park_rings, 0.05, Color("5f8f52")))
	if not pitch_rings.is_empty():
		_add_mesh("Pitches", InnerWestMesh.draped_polygons(height_grid, pitch_rings, 0.07, Color("6d955a")))


func _build_roads_and_rail() -> void:
	var bridges_by_id: Dictionary = {}
	for bridge in data.get("bridges", []):
		bridges_by_id[String(bridge.get("id", ""))] = bridge

	var road_paths: Array = []
	var road_widths: Array = []
	var road_ys: Array = []
	var bridge_bodies := 0
	var barrier_mesh := SurfaceTool.new()
	barrier_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var barrier_faces := PackedVector3Array()
	var deck_body := StaticBody3D.new()
	deck_body.name = "BridgeDeckCollision"
	var roads_by_id: Dictionary = {}

	for road in data.get("roads", []):
		var road_id := str(road.get("id", ""))
		roads_by_id[road_id] = road
		var path: Array = road.get("points", [])
		if path.size() < 2:
			continue
		var widths: Array = []
		var ys: PackedFloat32Array = PackedFloat32Array()
		var override: PackedFloat32Array = PackedFloat32Array()
		if road.get("bridge", false) and not road.get("tunnel", false):
			if bridges_by_id.has(road_id):
				var clearance := float(bridges_by_id[road_id].get("clearanceM", 6.0))
				override = InnerWestMesh.bridge_deck_ys(height_grid, path, clearance, WATER_Y)
			else:
				# viaduct over land: lift the deck off the ground generically
				var terrain := InnerWestMesh.height_along(height_grid, path)
				override = PackedFloat32Array()
				override.resize(terrain.size())
				for index in terrain.size():
					override[index] = terrain[index] + VIADUCT_LIFT
			# barriers + convex deck slabs for this bridge
			var barriers := InnerWestMesh.bridge_barriers(road, override, 1.1)
			if barriers["mesh"] != null:
				var instance := MeshInstance3D.new()
				instance.name = "BridgeBarrier%d" % bridge_bodies
				instance.mesh = barriers["mesh"]
				add_child(instance)
			barrier_faces.append_array(barriers["faces"])
			_add_deck_colliders(deck_body, road, override)
			bridge_bodies += 1
		road_paths.append(path)
		road_widths.append(float(road.get("widthM", 8.0)))
		road_ys.append(override)

	if bridge_bodies > 0 and deck_body.get_child_count() > 0:
		add_child(deck_body)
	geometry_counts["BridgeDecks"] = {"bridges": bridge_bodies, "colliders": deck_body.get_child_count()}
	if barrier_faces.size() >= 3:
		var body := StaticBody3D.new()
		body.name = "BridgeBarrierCollision"
		add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(barrier_faces)
		collider.shape = shape
		body.add_child(collider)

	_add_mesh("Roads", InnerWestMesh.draped_paths(height_grid, road_paths, road_widths, 0.06, Color("30353a"), road_ys))
	_add_mesh(
		"Junctions",
		InnerWestMesh.draped_junctions(height_grid, data.get("junctions", []), roads_by_id, 0.056, Color("30353a")),
	)

	# rail corridors: dark ballast + two rails
	var rail_paths: Array = []
	var rail_ys: Array = []
	var left_rails: Array = []
	var right_rails: Array = []
	for rail in data.get("railCorridors", []):
		var path: Array = rail.get("points", [])
		if path.size() < 2:
			continue
		var ys: PackedFloat32Array = PackedFloat32Array()
		if rail.get("bridge", false) and not rail.get("tunnel", false):
			var terrain := InnerWestMesh.height_along(height_grid, path)
			ys.resize(terrain.size())
			for index in terrain.size():
				ys[index] = terrain[index] + RAIL_LIFT
		rail_paths.append(path)
		rail_ys.append(ys)
		left_rails.append(_rail_line(path, ys, 0.72))
		right_rails.append(_rail_line(path, ys, -0.72))
	if not rail_paths.is_empty():
		var widths: Array = []
		for index in rail_paths.size():
			widths.append(3.6)
		_add_mesh("RailBallast", InnerWestMesh.draped_paths(height_grid, rail_paths, widths, 0.09, Color("4a4741"), rail_ys))
		# draped_paths expects a flat list of paths and one width per path. The
		# old nested arrays passed Arrays to float(), aborting the whole Inner
		# West build before the rails were created.
		var side_paths: Array = []
		side_paths.append_array(left_rails)
		side_paths.append_array(right_rails)
		var side_widths: Array = []
		for index in side_paths.size():
			side_widths.append(0.16)
		_add_mesh("Rails", InnerWestMesh.draped_paths(height_grid, side_paths, side_widths, 0.16, Color("8d949c")))


func _rail_line(path: Array, ys: PackedFloat32Array, offset: float) -> Array:
	var out: Array = []
	for index in range(path.size() - 1):
		var a := Vector2(float(path[index][0]), float(path[index][1]))
		var b := Vector2(float(path[index + 1][0]), float(path[index + 1][1]))
		var direction := (b - a).normalized() if b.distance_to(a) > 0.001 else Vector2(1, 0)
		var normal := Vector2(-direction.y, direction.x)
		out.append([a.x + normal.x * offset, a.y + normal.y * offset])
	out.append(out[out.size() - 1] if not out.is_empty() else [0.0, 0.0])
	return out


## Convex segment slabs under bridge decks (the Phase 5 midspan lesson: a box
## body can catch on coplanar trimesh seams, convex slabs cannot).
func _add_deck_colliders(body: StaticBody3D, road: Dictionary, ys: PackedFloat32Array) -> void:
	var points: Array = road.get("points", [])
	if points.size() < 2 or ys.size() != points.size():
		return
	var width := float(road.get("widthM", 8.0)) + 0.36
	for index in range(points.size() - 1):
		var a := Vector2(float(points[index][0]), float(points[index][1]))
		var b := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var mid := (a + b) * 0.5
		var angle := (b - a).angle()
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 0.5, length + 0.05)
		collider.shape = shape
		collider.position = Vector3(mid.x, (ys[index] + ys[index + 1]) * 0.5 - 0.28, mid.y)
		collider.rotation.y = -angle
		body.add_child(collider)


func _build_footpaths() -> void:
	var paths: Array = []
	var widths: Array = []
	var step_surfaces: Array = []
	var step_faces := PackedVector3Array()
	for footpath in data.get("footpaths", []):
		var path: Array = footpath.get("points", [])
		if path.size() < 2:
			continue
		if String(footpath.get("kind", "")) == "steps":
			var stairs := InnerWestMesh.steps_mesh(height_grid, path, float(footpath.get("widthM", 1.8)), Color("b7ab93"))
			if stairs["mesh"] != null:
				step_surfaces.append(stairs["mesh"])
			step_faces.append_array(stairs["faces"])
			continue
		paths.append(path)
		widths.append(float(footpath.get("widthM", 1.8)))
	if not paths.is_empty():
		_add_mesh("Footpaths", InnerWestMesh.draped_paths(height_grid, paths, widths, 0.10, Color("bbb6a6")))
	for index in step_surfaces.size():
		_add_mesh("Steps%d" % index, step_surfaces[index])
	if step_faces.size() >= 3:
		var body := StaticBody3D.new()
		body.name = "StepsCollision"
		add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(step_faces)
		collider.shape = shape
		body.add_child(collider)
		geometry_counts["StepsCollision"] = {"triangles": step_faces.size() / 3}


func _build_crossings() -> void:
	var roads: Dictionary = {}
	for road in data.get("roads", []):
		roads[str(road.get("id", ""))] = road
	var rows: Array = []
	for source in data.get("crossings", []):
		var row: Dictionary = source.duplicate(true)
		var angle := float(row.get("angleRad", 0.0))
		if row.get("kind", "") == "node":
			# real OSM crossing nodes have no direction: use the nearest road
			var road: Dictionary = _nearest_road(roads, float(row.get("x", 0.0)), float(row.get("z", 0.0)))
			if not road.is_empty():
				var hit := InnerWestMesh._nearest_segment(
					road.get("points", []),
					Vector2(float(row.get("x", 0.0)), float(row.get("z", 0.0))),
				)
				if not hit.is_empty():
					var direction: Vector2 = hit["direction"]
					angle = direction.angle() + PI / 2.0
					row["lengthM"] = float(road.get("widthM", 8.0)) + 1.0
		row["angleRad"] = angle
		rows.append(row)
	_add_mesh("Crossings", InnerWestMesh.draped_crossings(height_grid, rows, 0.12, Color("e9e4d2")))


func _nearest_road(roads: Dictionary, x: float, z: float) -> Dictionary:
	var best := {}
	var best_distance := 18.0
	for road_id in roads:
		var road: Dictionary = roads[road_id]
		if road.get("tunnel", false):
			continue
		var hit := InnerWestMesh._nearest_segment(
			road.get("points", []), Vector2(x, z)
		)
		if hit.is_empty():
			continue
		if float(hit["distance"]) < best_distance:
			best_distance = float(hit["distance"])
			best = road
	return best


func _build_buildings() -> void:
	var road_hash := InnerWestMesh.road_vertex_hash(data.get("roads", []))
	var built := InnerWestBuildings.styled_buildings(
		height_grid, data.get("buildings", []), road_hash, neighbourhood_names
	)
	if built["mesh"] != null:
		_add_mesh("Buildings", built["mesh"])
	_add_chunk_bodies("BuildingCollision", built["chunkFaces"], false)
	geometry_counts["Buildings"] = {
		"built": int(built["built"]),
		"skipped": int(built["skipped"]),
		"triangles": int(built["triangles"]),
		"byStyle": built["byStyle"],
	}
	if int(built["skipped"]) > 0:
		push_warning("InnerWestWorld: skipped %d malformed building footprints" % int(built["skipped"]))


func _build_trees() -> void:
	var real_trees: Array = data.get("trees", [])
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	_rng_seed(7)
	for tree in real_trees:
		var x := float(tree.get("x", 0.0))
		var z := float(tree.get("z", 0.0))
		_push_tree(transforms, colors, x, z, 0.8 + _rng() * 0.6)
	# park scatter: deterministic, seeded per park
	for park in data.get("parks", []):
		for ring in park.get("rings", []):
			var points := InnerWestMesh._clean_ring(ring)
			if points.size() < 3:
				continue
			var area := absf(InnerWestMesh._signed_area(points))
			var count := int(area / 420.0)
			if count < 1:
				continue
			var rect := _ring_bounds(points)
			_rng_seed(int(absi(String(park.get("id", "0")).hash())))
			for index in count:
				var x: float = float(rect[0] + _rng() * (rect[2] - rect[0]))
				var z: float = float(rect[1] + _rng() * (rect[3] - rect[1]))
				if Geometry2D.is_point_in_polygon(Vector2(x, z), points):
					_push_tree(transforms, colors, x, z, 0.75 + _rng() * 0.7)
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = InnerWestMesh.tree_mesh()
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, colors[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Trees"
	instance.multimesh = multimesh
	add_child(instance)
	geometry_counts["Trees"] = {"instances": transforms.size()}


func _push_tree(transforms: Array[Transform3D], colors: Array[Color], x: float, z: float, scale: float) -> void:
	var y := InnerWestMesh.height_at(height_grid, x, z)
	if y < -1.0:
		return  # in the water
	var basis := Basis(Vector3.UP, _rng() * TAU).scaled(Vector3(scale, scale * (0.85 + _rng() * 0.3), scale))
	transforms.append(Transform3D(basis, Vector3(x, y - 0.15, z)))
	var tint := 0.86 + _rng() * 0.2
	colors.append(Color(tint, tint, tint * (0.94 + _rng() * 0.1)))


func _ring_bounds(points: PackedVector2Array) -> Array:
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


var _rng_state := 1


func _rng_seed(seed_value: int) -> void:
	_rng_state = 1103515245 * (absi(seed_value) % 2147483647 + 1) + 12345


func _rng() -> float:
	_rng_state = (_rng_state * 1103515245 + 12345) % 2147483648
	return float(_rng_state) / 2147483648.0


func _build_landmarks() -> void:
	var bridge_script = load("res://sydney/inner_west/anzac_bridge.gd")
	var bridge = bridge_script.new()
	bridge.name = "AnzacBridge"
	var result: Dictionary = bridge.build_from_world(self)
	if result.ok:
		add_child(bridge)
		geometry_counts["AnzacBridge"] = bridge.stats
	else:
		bridge.free()
		push_warning("InnerWestWorld: Anzac Bridge not built: " + String(result.get("reason", "?")))


# ------------------------------------------------------------- utilities --
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


func _add_chunk_bodies(prefix: String, chunk_faces: Array, backface: bool) -> void:
	var built := 0
	for index in chunk_faces.size():
		var faces: PackedVector3Array = chunk_faces[index]
		if faces.size() < 3:
			continue
		var body := StaticBody3D.new()
		body.name = "%s%d" % [prefix, index]
		add_child(body)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		if backface:
			shape.backface_collision = true
		shape.set_faces(faces)
		collider.shape = shape
		body.add_child(collider)
		built += 1
	geometry_counts[prefix] = {
		"bodies": built,
		"triangles": chunk_faces.reduce(
			func(acc: int, faces: PackedVector3Array) -> int: return acc + faces.size() / 3, 0
		),
	}
