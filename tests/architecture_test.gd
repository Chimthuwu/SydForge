extends SceneTree
const Assembler = preload("res://sydney/architecture/assembler.gd")
const Prototype = preload("res://sydney/architecture/prototype.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("PASS: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var assembler := Assembler.new()
	for module in Assembler.MODULES:
		var source := assembler._source(module)
		var bounds: AABB = source.bounds
		check(bounds.size.x > 0 and bounds.size.y > 0, module + " imports with nonzero dimensions")
		check(source.mesh.surface_get_material(0) != null, module + " has imported material")
		print("ASSET ", module, " ", bounds)
	for row in Prototype.examples():
		var p := Assembler.plan(row)
		check(not p.is_empty(), str(row.id) + " supported")
		check(p == Assembler.plan(row), str(row.id) + " deterministic")
		var maximum := 0.0
		var aligned := true
		var oriented := true
		var widths := true
		for bay in p.bays:
			var t: Transform3D = bay.transform
			maximum = maxf(maximum, t.origin.y + bay.height)
			var a: Vector2 = p.ring[bay.edge]
			var b: Vector2 = p.ring[(bay.edge + 1) % p.ring.size()]
			var point := Vector2(t.origin.x, t.origin.z)
			aligned = aligned and absf(Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) - Assembler.FACADE_OFFSET) < 0.001
			var outside := point + Vector2(t.basis.z.x, t.basis.z.z)
			oriented = oriented and not Geometry2D.is_point_in_polygon(outside, p.ring)
			oriented = oriented and absf(t.basis.determinant() - 1.0) < 0.001 and t.basis.y.is_equal_approx(Vector3.UP)
			widths = widths and bay.width > 0.0 and bay.width < 5.0
		check(aligned, str(row.id) + " bays follow footprint edges")
		check(oriented, str(row.id) + " right handed upright module orientation")
		check(widths, str(row.id) + " bounded bay dimensions")
		check(is_equal_approx(maximum, row.heightM), str(row.id) + " exact height including ground floor")
		var reversed: Dictionary = row.duplicate(true)
		reversed.ring.reverse()
		var reverse_plan := Assembler.plan(reversed)
		check(reverse_plan.bays.size() == p.bays.size(), "clockwise ring preserves bay count")
	var concave := {"id": "concave", "heightM": 12, "ring": [[0,0],[12,0],[12,4],[4,4],[4,12],[0,12]]}
	check(Assembler.plan(concave).is_empty(), "concave footprint rejected for modules")
	var fallback := SydneyMesh.buildings([concave])
	check(fallback.built == 1 and fallback.faces.size() > 0, "concave fallback keeps exact shell and collision")
	var engine_mesh := SydneyMesh.engine_building_mesh(fallback.mesh)
	var arrays := engine_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var engine_faces := SydneyMesh.engine_building_faces(fallback.faces)
	var clockwise := true
	var parity := true
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		clockwise = clockwise and (b-a).cross(c-a).dot(normals[indices[i]]) < 0
		parity = parity and a == engine_faces[i] and b == engine_faces[i+1] and c == engine_faces[i+2]
	check(clockwise, "engine mesh uses clockwise exterior fronts")
	check(parity, "engine collision triangles exactly match indexed render triangles")
	check(engine_mesh.surface_get_material(0).cull_mode == BaseMaterial3D.CULL_BACK, "engine front faces use back-face culling")
	check(Assembler.plan({"ring": [[0,0],[1,0],[2,0]], "heightM": 12}).is_empty(), "degenerate footprint rejected")
	var hole: Dictionary = Prototype.examples()[0].duplicate(true)
	hole.holes = [[[2,2],[3,2],[3,3]]]
	check(Assembler.plan(hole).is_empty(), "holes not silently filled by assembler")
	var invalid: Dictionary = Prototype.examples()[0].duplicate(true)
	invalid.heightM = NAN
	check(Assembler.plan(invalid).is_empty(), "nonfinite height rejected")
	var node := assembler.assemble(Prototype.examples())
	check(node.get_meta("buildings").size() == 5, "all five prototype compositions assembled")
	check(node.get_child_count() < 25, "module transforms batched by mesh")
	node.free()
	var world := SydneyWorld.new()
	check(world.load_world(), "Sydney integration loads")
	root.add_child(world)
	await physics_frame
	await physics_frame
	var selected := Assembler.pilot(world.data.buildings, world.player_spawn)
	check(selected.size() == 7, "seven reviewed buildings in the CBD pilot")
	var reordered: Array = world.data.buildings.duplicate()
	reordered.reverse()
	check(selected == Assembler.pilot(reordered, world.player_spawn), "pilot independent of source array order")
	check(world.geometry_counts.Buildings.built == 930, "all 930 geographic shells retained")
	check(world.geometry_counts.Architecture.fallback == 923, "remaining 923 use procedural fallback")
	var file := FileAccess.open("res://tests/architecture_pilot.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(selected, "\t"))
	file.close()
	for row in selected:
		var p := Assembler.plan(row)
		var a: Vector2 = p.ring[0]
		var b: Vector2 = p.ring[1]
		var mid := (a + b) * 0.5
		var outward := Vector2((b-a).y, -(b-a).x).normalized() * signf(SydneyMesh._signed_area(p.ring))
		var from := Vector3(mid.x + outward.x * 0.5, 2, mid.y + outward.y * 0.5)
		var to := Vector3(mid.x - outward.x * 0.5, 2, mid.y - outward.y * 0.5)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		check(not hit.is_empty() and hit.collider.name == "BuildingCollision", str(row.id) + " real physics wall collision")
		var center := Vector2.ZERO
		for point in p.ring:
			center += point
		center /= p.ring.size()
		var roof_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(center.x,p.height+2,center.y), Vector3(center.x,p.height-2,center.y)))
		check(not roof_hit.is_empty() and absf(roof_hit.position.y - p.height) < 0.01, str(row.id) + " roof collision at exact exported height")
	print("ARCHITECTURE ", world.geometry_counts.Architecture)
	print("TIMINGS ", world.build_times_ms)
	world.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
