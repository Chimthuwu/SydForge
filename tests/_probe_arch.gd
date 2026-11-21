extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var text := FileAccess.get_file_as_string("res://sydney/world/stage_b/world.json")
	var data: Dictionary = JSON.parse_string(text)
	var bridge = load("res://sydney/landmarks/harbour_bridge.gd").new()
	bridge.build()
	var rail = load("res://sydney/cbd/cbd_rail_network.gd").new()
	rail.build(data, bridge)
	var route: Array = rail.main_route_points
	var first: int = rail._descent_cut_first_index()
	var last: int = rail._descent_cut_last_index()
	print("first=", first, " last=", last)
	var out := ""
	for i in range(first, last + 1, 2):
		var p: Vector3 = route[i]
		out += "\tVector2(%.2f, %.2f),\n" % [p.x, p.z]
	print("---POINTS---")
	print(out)
	quit()
