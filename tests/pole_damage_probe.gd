extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	var cops = get_nodes_in_group("police_foot_patrol")
	print("POLICE_COUNT ", cops.size())
	if cops.is_empty():
		quit(); return
	var cop = cops[0] as Node3D
	print("POLICE_LAYER ", cop.get("collision_layer"), " MASK ", cop.get("collision_mask"))
	print("POLICE_HEALTH ", cop.get("health"), " DEAD ", cop.get("is_dead"))
	if cop.has_method("take_damage_at"):
		cop.call("take_damage_at", 25.0, cop.global_position, 1.0, Vector3.FORWARD)
		print("AFTER_HIT health=", cop.get("health"))
	for i in 6:
		if cop.has_method("take_damage_at"):
			cop.call("take_damage_at", 25.0, cop.global_position, 1.0, Vector3.FORWARD)
	print("AFTER_KILL health=", cop.get("health"), " DEAD=", cop.get("is_dead"))
	quit()
