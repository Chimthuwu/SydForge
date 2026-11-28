extends SceneTree
## Diagnostic: full test-scene reproduction of the winding check in
## tests/harbour_bridge_test.gd. Lists EVERY child of the bridge with type
## and per-surface mismatch counts, after 150 physics frames of settle.

func probe(child: Node, out: Array) -> void:
	if not (child is MeshInstance3D):
		out.append("SKIP %s (%s)" % [child.name, child.get_class()])
		return
	var mesh: ArrayMesh = child.mesh
	if mesh == null:
		out.append("SKIP %s (MeshInstance3D, null mesh)" % child.name)
		return
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var bad := 0
		var zero := 0
		var count := ids.size() if ids.size() > 0 else verts.size()
		for i in range(0, count, 3):
			var a: int = ids[i] if ids.size() > 0 else i
			var b: int = ids[i+1] if ids.size() > 0 else i+1
			var c: int = ids[i+2] if ids.size() > 0 else i+2
			if a >= verts.size() or b >= verts.size() or c >= verts.size():
				bad += 1
				continue
			var cross := (verts[c]-verts[a]).cross(verts[b]-verts[a])
			if cross.length() < 0.000001:
				zero += 1
				continue
			if cross.dot(normals[a]) <= 0:
				bad += 1
		out.append("MESH %s surf=%d tris=%d bad=%d zero=%d" % [child.name, s, count/3, bad, zero])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = load("res://sydney/sydney_bridge_test.tscn").instantiate()
	root.add_child(world)
	for i in 150:
		await physics_frame
	var bridge: Node3D = world.sydney_world.get_node("HarbourBridge")
	var out := []
	for child in bridge.get_children():
		probe(child, out)
	for line in out:
		print("BRIDGE ", line)
	world.queue_free()
	quit(0)
