extends SceneTree
## Diagnostic: exact reproduction of tests/harbour_bridge_test.gd winding
## check, but prints the offending child the moment winding turns false.

var world: Node3D

func settle(count: int) -> void:
	for i in count:
		await physics_frame

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://sydney/sydney_bridge_test.tscn").instantiate()
	root.add_child(world)
	var bridge: Node3D = world.sydney_world.get_node("HarbourBridge")
	await settle(150)
	var winding := true
	for child in bridge.get_children():
		if not child is MeshInstance3D or child.name in ["ApproachLand","HarbourExtension","MilsonsStreets"]:
			continue
		var mesh: ArrayMesh = child.mesh
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var ids := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			ids = arrays[Mesh.ARRAY_INDEX]
		var count := ids.size() if ids.size()>0 else verts.size()
		for i in range(0,count,3):
			var a := ids[i] if ids.size()>0 else i
			var b := ids[i+1] if ids.size()>0 else i+1
			var c := ids[i+2] if ids.size()>0 else i+2
			var cross := (verts[c]-verts[a]).cross(verts[b]-verts[a])
			if cross.dot(normals[a])<=0:
				if winding:
					print("OFFENDER ", child.name, " tri_idx=", i, " a=", a, " b=", b, " c=", c,
						" verts.size=", verts.size(), " normals.size=", normals.size(),
						" cross=", cross, " normal_a=", normals[a],
						" id_ranges=", a<verts.size(), b<verts.size(), c<verts.size())
				winding = false
	print("WINDING=", winding)
	world.queue_free()
	await process_frame
	quit(0)
