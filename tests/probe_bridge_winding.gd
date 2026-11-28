extends SceneTree
# One-off probe: report which HarbourBridge mesh child breaks the winding check.
func check_mesh(child: MeshInstance3D, report: Array) -> void:
	var mesh: ArrayMesh = child.mesh
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	if arrays == null:
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.size() == 0:
		return
	var ids := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		ids = arrays[Mesh.ARRAY_INDEX]
	var bad := 0
	var first_bad := -1
	var cross_mag := 0.0
	var dot := 0.0
	var count := ids.size() if ids.size() > 0 else verts.size()
	for i in range(0, count, 3):
		var a := ids[i] if ids.size() > 0 else i
		var b := ids[i+1] if ids.size() > 0 else i+1
		var c := ids[i+2] if ids.size() > 0 else i+2
		if a >= verts.size() or b >= verts.size() or c >= verts.size():
			bad += 1
			continue
		var cross := (verts[c]-verts[a]).cross(verts[b]-verts[a])
		if cross.length() < 0.000001:
			continue
		var d: float = cross.dot(normals[a])
		if d <= 0:
			bad += 1
			if first_bad < 0:
				first_bad = i
				cross_mag = cross.length()
				dot = d
	report.append("%s tris=%d bad=%d first_bad_tri=%d cross_len=%.4f dot=%.4f" % [child.name, count/3, bad, first_bad, cross_mag, dot])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = load("res://sydney/sydney_bridge_test.tscn").instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var bridge: Node3D = world.sydney_world.get_node("HarbourBridge")
	var report := []
	for child in bridge.get_children():
		if child is MeshInstance3D and child.name not in ["ApproachLand", "HarbourExtension", "MilsonsStreets"]:
			check_mesh(child, report)
	for line in report:
		print("PROBE ", line)
	world.queue_free()
	quit(0)
