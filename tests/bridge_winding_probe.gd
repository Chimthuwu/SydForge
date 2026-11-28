extends SceneTree
## Diagnostic: which HarbourBridge mesh/surface trips the clockwise-winding
## check in tests/harbour_bridge_test.gd? Builds the bridge standalone and
## reports per-child mismatch counts and worst-case normal dot.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var bridge = load("res://sydney/landmarks/harbour_bridge.gd").new()
	bridge.build()
	for child in bridge.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh: ArrayMesh = child.mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var total := 0
			var bad := 0
			var zero := 0
			var worst := 1e9
			var first_bad := 0
			var count := ids.size() if ids.size() > 0 else verts.size()
			for i in range(0, count, 3):
				var a: int = ids[i] if ids.size() > 0 else i
				var b: int = ids[i+1] if ids.size() > 0 else i+1
				var c: int = ids[i+2] if ids.size() > 0 else i+2
				var cross := (verts[c]-verts[a]).cross(verts[b]-verts[a])
				total += 1
				if cross.length() < 0.000001:
					zero += 1
					continue
				var d := cross.dot(normals[a])
				if d <= 0:
					bad += 1
					if d < worst:
						worst = d
						first_bad = i
			if bad > 0 or zero > 0:
				print("MISMATCH ", child.name, " surf=", s, " tris=", total, " bad=", bad, " zero=", zero, " worst_dot=", worst, " first_bad_idx=", first_bad)
			else:
				print("OK ", child.name, " surf=", s, " tris=", total)
	bridge.free()
	quit(0)
