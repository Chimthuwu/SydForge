extends SceneTree

## Phase 6A harbour water checks — data integrity, world integration, the
## superseded Stage A water, collision behaviour, and that the Opera House and
## Harbour Bridge are untouched.
##   $env:APPDATA = './.runtime'
##   ./Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path . \
##       --script res://tests/harbour_water_test.gd --log-file tests/harbour_water_test.log

var checks := 0
var failures := 0


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func _initialize() -> void:
	call_deferred("run")


func _settle(frame_count: int) -> void:
	for i in frame_count:
		await physics_frame


func _place(world: Node3D, position: Vector3) -> void:
	world.player.global_position = position
	world.player.velocity = Vector3.ZERO


func _face(world: Node3D, target: Vector3) -> void:
	var forward: Vector3 = target - world.player.global_position
	forward.y = 0.0
	if forward.length() > 0.01:
		forward = forward.normalized()
		world.rig.yaw = atan2(-forward.x, -forward.z)


func _walk(frames: int) -> void:
	Input.action_press("forward")
	for i in frames:
		await physics_frame
	Input.action_release("forward")


func _jump_forward(frames: int) -> void:
	Input.action_press("forward")
	Input.action_press("jump")
	await physics_frame
	await physics_frame
	Input.action_release("jump")
	for i in frames - 2:
		await physics_frame
	Input.action_release("forward")


## Closest point on any harbour water ring boundary to `from`.
func _nearest_shore(harbour: Node, from: Vector2) -> Vector2:
	var best := from
	var best_distance := INF
	for ring in harbour.rings:
		for index in ring.size():
			var a: Vector2 = ring[index]
			var b: Vector2 = ring[(index + 1) % ring.size()]
			var closest := Geometry2D.get_closest_point_to_segment(from, a, b)
			var distance := closest.distance_to(from)
			if distance < best_distance:
				best_distance = distance
				best = closest
	return best


func _surface_checksum(mesh: ArrayMesh) -> float:
	var total := 0.0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for index in vertices.size():
			total += vertices[index].x + vertices[index].y * 2.0 + vertices[index].z * 3.0
		for color in colors:
			total += color.r + color.g * 2.0 + color.b * 3.0
	return total


func run() -> void:
	# ------------------------------------------------ module data integrity ----
	var harbour_script = preload("res://sydney/harbour/harbour_water.gd")
	var standalone: Node = harbour_script.new()
	check(standalone.build(), "harbour module builds from its data file")
	check(standalone.rings.size() >= 5, "several harbour water rings (%d)" % standalone.rings.size())
	check(standalone.stats.get("waterAreaM2", 0.0) > 4.0e6,
		"harbour water area is large (%.0f m2)" % standalone.stats.get("waterAreaM2", 0.0))
	check(standalone.stats.get("waterAreaM2", 0.0) < 6.0e6,
		"harbour water area is bounded (%.0f m2)" % standalone.stats.get("waterAreaM2", 0.0))
	for ring in standalone.rings:
		var points: PackedVector2Array = ring
		check(points.size() >= 3, "water ring has at least 3 vertices")
		var finite := true
		for point in points:
			if is_nan(point.x) or is_inf(point.x) or is_nan(point.y) or is_inf(point.y):
				finite = false
		check(finite, "water ring vertices are all finite")
		check(points[0].distance_to(points[points.size() - 1]) > 0.001,
			"water ring does not repeat its closing vertex")

	var coverage := {
		"Sydney Cove": [500.0, -1780.0, true],
		"Circular Quay wharf water": [340.0, -1790.0, true],
		"Farm Cove": [800.0, -1730.0, true],
		"Woolloomooloo Bay": [1150.0, -1500.0, true],
		"Darling Harbour": [-650.0, -300.0, true],
		"Blackwattle Bay": [-1150.0, 0.0, true],
		"under the bridge midspan": [250.0, -2300.0, true],
		"eastern harbour": [1200.0, -2200.0, true],
		"Opera House podium": [658.7, -1763.8, false],
		"Opera House forecourt": [632.1, -1650.9, false],
		"Circular Quay spawn": [219.9, -1755.7, false],
		"Royal Botanic Garden": [700.0, -1420.0, false],
		"Town Hall CBD": [-42.8, -466.5, false],
		"Glebe land west of Blackwattle": [-1350.0, 0.0, false],
		"Pyrmont land east of Blackwattle": [-950.0, -150.0, false],
	}
	for name in coverage:
		var entry: Array = coverage[name]
		var expected: bool = entry[2]
		check(standalone.is_water(entry[0], entry[1]) == expected,
			"%s is %s" % [name, "water" if expected else "dry land"])

	# determinism: an independent rebuild must produce identical geometry
	var second: Node = harbour_script.new()
	second.build()
	var first_mesh: ArrayMesh = standalone.get_node("HarbourWaterSurface").mesh
	var second_mesh: ArrayMesh = second.get_node("HarbourWaterSurface").mesh
	check(absf(_surface_checksum(first_mesh) - _surface_checksum(second_mesh)) < 0.001,
		"rebuild is deterministic (checksum match)")
	second.free()
	standalone.free()
	await process_frame

	# ---------------------------------------------------- real world scene ----
	var scene: Node3D = load("res://sydney/sydney_test.tscn").instantiate()
	root.add_child(scene)
	await _settle(200)
	var world: SydneyWorld = scene.sydney_world
	var harbour: Node = world.get_node_or_null("HarbourWater")
	check(harbour != null, "the world contains the harbour water module")
	if harbour == null:
		_finish(scene)
		return

	# node structure and stats
	for node_name in ["HarbourWaterSurface", "HarbourIslands", "HarbourPonds",
			"HarbourLand", "HarbourWaterCollision", "HarbourLandCollision"]:
		check(harbour.get_node_or_null(node_name) != null, "harbour child node %s exists" % node_name)
	var world_stats: Dictionary = world.geometry_counts.get("HarbourWater", {})
	check(world_stats.get("waterTriangles", 0) > 2000,
		"water surface has many triangles (%d)" % int(world_stats.get("waterTriangles", 0)))
	check(world_stats.get("waterTriangles", 0) < 6000,
		"water surface triangle budget is respected (%d)" % int(world_stats.get("waterTriangles", 0)))
	check(world_stats.get("landCollisionTriangles", 0) > 500,
		"land collar has floor collision (%d triangles)" % int(world_stats.get("landCollisionTriangles", 0)))

	# superseded Stage A water
	var old_water: Node = world.get_node_or_null("Water")
	check(old_water == null or not old_water.visible, "the Stage A Water mesh is superseded")
	check(world.get_node_or_null("WaterCollision") == null,
		"the Stage A WaterCollision body is superseded")
	var bridge_extension: Node = world.get_node_or_null("HarbourBridge/HarbourExtension")
	check(bridge_extension == null or not bridge_extension.visible,
		"the bridge site water mesh is superseded")

	# landmarks intact
	var opera: Node = world.get_node_or_null("OperaHouse")
	check(opera != null and opera.visible, "the Opera House is present and visible")
	if opera != null:
		check(opera.get_node_or_null("OperaCollision") != null, "Opera House collision is present")
	var bridge: Node = world.get_node_or_null("HarbourBridge")
	check(bridge != null and bridge.visible, "the Harbour Bridge is present and visible")

	# water surface audit
	var surface_mesh: ArrayMesh = harbour.get_node("HarbourWaterSurface").mesh
	var bad_geometry := 0
	var non_finite := 0
	var wrong_y := 0
	var bad_color := 0
	var bad_normal := 0
	var triangles := 0
	var water_y := 0.02
	for surface_index in surface_mesh.get_surface_count():
		var arrays := surface_mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for index in range(0, vertices.size(), 3):
			triangles += 1
			var a := vertices[index]
			var b := vertices[index + 1]
			var c := vertices[index + 2]
			if (b - a).cross(c - a).length() < 1e-6:
				bad_geometry += 1
			for point in [a, b, c]:
				if is_nan(point.x) or is_inf(point.x) or is_nan(point.y) or is_inf(point.y) \
						or is_nan(point.z) or is_inf(point.z):
					non_finite += 1
				if absf(point.y - water_y) > 0.0001:
					wrong_y += 1
			for color in [colors[index], colors[index + 1], colors[index + 2]]:
				if color.r < 0.8 or color.r > 1.2 or color.g < 0.8 or color.g > 1.25 or color.b < 0.8 or color.b > 1.2:
					bad_color += 1
			for normal in [normals[index], normals[index + 1], normals[index + 2]]:
				if normal.dot(Vector3.UP) < 0.999:
					bad_normal += 1
	check(triangles > 2000, "water surface is fully triangulated (%d triangles)" % triangles)
	check(bad_geometry == 0, "water surface has zero degenerate triangles")
	check(non_finite == 0, "water surface vertices are all finite")
	check(wrong_y == 0, "water surface sits at y 0.02 (above ground, under footpaths)")
	check(bad_color == 0, "vertex colour variation stays within subtle bounds")
	check(bad_normal == 0, "water normals point up")
	var material: Material = surface_mesh.surface_get_material(0)
	check(material is ShaderMaterial or material is StandardMaterial3D,
		"water material is attached (%s)" % str(material))

	# ponds preserved
	var ponds: MeshInstance3D = harbour.get_node_or_null("HarbourPonds")
	check(ponds != null and ponds.mesh != null, "non-harbour Stage A ponds are preserved")
	check(not harbour.is_water(351.0, -225.0), "a preserved pond area is not harbour water")

	# collision audit
	var barrier: StaticBody3D = harbour.get_node("HarbourWaterCollision")
	var collider: CollisionShape3D = barrier.get_child(0)
	var shape := collider.shape as ConcavePolygonShape3D
	check(shape != null and shape.backface_collision, "barrier is one backface-colliding concave shape")
	var faces: PackedVector3Array = shape.get_faces()
	var stats: Dictionary = world.geometry_counts.get("HarbourWater", {})
	check(faces.size() == int(stats.get("collisionEdges", 0)) * 6,
		"barrier faces match every ring edge twice (%d faces)" % faces.size())
	check(faces.size() > 3000 and faces.size() < 24000,
		"barrier is one light mesh (%d faces)" % faces.size())
	var max_wall := 0.0
	for index in range(0, faces.size(), 3):
		max_wall = maxf(max_wall, maxf(faces[index].y, maxf(faces[index + 1].y, faces[index + 2].y)))
	check(absf(max_wall - 2.4) < 0.001, "barrier walls reach 2.4 m (unclearable jump apex 1.33 m)")

	# water must not cover Stage A buildings (sampled)
	var buildings: Array = world.data.get("buildings", [])
	var wet_buildings := 0
	for index in range(0, buildings.size(), 10):
		var ring: Array = buildings[index].get("ring", [])
		if ring.size() < 3:
			continue
		var cx := 0.0
		var cz := 0.0
		for point in ring:
			cx += float(point[0])
			cz += float(point[1])
		if harbour.is_water(cx / ring.size(), cz / ring.size()):
			wet_buildings += 1
	check(wet_buildings == 0, "no sampled Stage A building centroid is in water (%d)" % wet_buildings)

	# ---------------------------------------------------- player behaviour ----
	var spawn: Vector3 = scene.player.global_position
	check(not harbour.is_water(spawn.x, spawn.z), "Circular Quay spawn is on land")

	# Walk into Sydney Cove from the promenade.
	var shore := _nearest_shore(harbour, Vector2(spawn.x, spawn.z))
	var inland := (Vector2(spawn.x, spawn.z) - shore).normalized()
	var start := shore + inland * 3.0
	_place(scene, Vector3(start.x, 0.4, start.y))
	await _settle(25)
	check(not harbour.is_water(start.x, start.y), "cove walk start point is on land")
	_face(scene, Vector3(shore.x, 0.0, shore.y))
	await _walk(180)
	var stopped := Vector2(scene.player.global_position.x, scene.player.global_position.z)
	check(not harbour.is_water(stopped.x, stopped.y), "player cannot walk into Sydney Cove")
	check(_nearest_shore(harbour, stopped).distance_to(stopped) < 2.5,
		"player stops at the rendered shoreline (%.2f m)" % _nearest_shore(harbour, stopped).distance_to(stopped))
	check(scene.player.global_position.y > -0.5, "player stays on the promenade surface")

	await _jump_forward(150)
	var jumped := Vector2(scene.player.global_position.x, scene.player.global_position.z)
	check(not harbour.is_water(jumped.x, jumped.y), "jumping cannot carry the player over the shoreline")

	# Walk into Darling Harbour from the east shore (new water).
	var darling_from := Vector2(-480.0, -300.0)
	var darling_shore := _nearest_shore(harbour, darling_from)
	var darling_inland := (darling_from - darling_shore).normalized()
	var darling_start := darling_shore + darling_inland * 3.0
	_place(scene, Vector3(darling_start.x, 0.4, darling_start.y))
	await _settle(25)
	check(not harbour.is_water(darling_start.x, darling_start.y), "Darling Harbour walk start is on land")
	_face(scene, Vector3(darling_shore.x, 0.0, darling_shore.y))
	await _walk(240)
	var darling_stopped := Vector2(scene.player.global_position.x, scene.player.global_position.z)
	check(not harbour.is_water(darling_stopped.x, darling_stopped.y),
		"player cannot walk into Darling Harbour")
	check(_nearest_shore(harbour, darling_stopped).distance_to(darling_stopped) < 2.5,
		"player stops at the Darling Harbour shoreline (%.2f m)" % _nearest_shore(harbour, darling_stopped).distance_to(darling_stopped))
	check(scene.player.global_position.y > -0.5, "player stands on the Darling Harbour shore")

	# Walk into Blackwattle Bay from Pyrmont collar land (new water + new floor).
	_place(scene, Vector3(-950.0, 0.4, -300.0))
	await _settle(25)
	check(scene.player.global_position.y > -0.5, "Pyrmont collar land is walkable (no fall-through)")
	check(not harbour.is_water(-950.0, -300.0), "Blackwattle walk start is on land")
	var black_from := Vector2(-950.0, -300.0)
	var black_shore := _nearest_shore(harbour, black_from)
	var black_inland := (black_from - black_shore).normalized()
	var black_start := black_shore + black_inland * 3.0
	_place(scene, Vector3(black_start.x, 0.4, black_start.y))
	await _settle(25)
	_face(scene, Vector3(black_shore.x, 0.0, black_shore.y))
	await _walk(240)
	var black_stopped := Vector2(scene.player.global_position.x, scene.player.global_position.z)
	check(not harbour.is_water(black_stopped.x, black_stopped.y),
		"player cannot walk into Blackwattle Bay")
	check(_nearest_shore(harbour, black_stopped).distance_to(black_stopped) < 2.5,
		"player stops at the Blackwattle shoreline (%.2f m)" % _nearest_shore(harbour, black_stopped).distance_to(black_stopped))

	print("WORLD BUILD ", world.build_times_ms)
	_finish(scene)


func _finish(scene: Node3D) -> void:
	print("RESULT: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
