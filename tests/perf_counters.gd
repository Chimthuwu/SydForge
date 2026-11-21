extends SceneTree

## Windowed renderer counters for the canonical Sydney scene. Run without
## --headless so the real Compatibility renderer submits draw calls.

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var scene: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	scene = CbdDistrictScript.new()
	get_root().add_child(scene)
	await _frames(360)
	var p := Performance
	var draw := int(p.get_monitor(p.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prim := int(p.get_monitor(p.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var mesh_instances := 0
	var lights := 0
	var audio3d := 0
	var nodes := 0
	for node in scene.find_children("*", "", true, false):
		nodes += 1
		if node is MeshInstance3D:
			mesh_instances += 1
		elif node is Light3D:
			lights += 1
		elif node is AudioStreamPlayer3D:
			audio3d += 1
	var traffic = scene.get_node_or_null("TrafficManager")
	var peds = scene.get_node_or_null("PedestrianManager")
	var wildlife = scene.get_node_or_null("WildlifeManager")
	print("PERF_NODES %d MESHES %d LIGHTS %d AUDIO3D %d" % [nodes, mesh_instances, lights, audio3d])
	print("PERF_DRAW_CALLS %d PRIMITIVES %d" % [draw, prim])
	print("PERF_ACTORS cars=%d peds=%d wildlife=%d" % [
		(traffic.get("active_vehicles") as Array).size(),
		(peds.get("active_pedestrians") as Array).size(),
		(wildlife.get("active_wildlife") as Array).size(),
	])
	quit(0)
