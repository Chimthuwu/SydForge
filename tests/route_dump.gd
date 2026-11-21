extends SceneTree

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := CbdDistrictScript.new()
	get_root().add_child(scene)
	for i in 20:
		await process_frame
	var railway = scene.get_node_or_null("CbdWorld/SydneyRailNetwork")
	if railway == null:
		for n in scene.find_children("*", "Node3D", true, false):
			if n.name == "SydneyRailNetwork":
				railway = n
				break
	if railway == null:
		print("NO RAILWAY")
		quit(1)
		return
	var route: Array = railway.get("main_route_points")
	for idx in [220, 234, 240, 248, 258, 260, 270, 285, 300, 314, 330, 348, 358]:
		if idx < route.size():
			var p: Vector3 = route[idx]
			print("ROUTE %d x=%.1f y=%.2f z=%.1f" % [idx, p.x, p.y, p.z])
	quit(0)
