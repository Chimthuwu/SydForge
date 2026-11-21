extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _check(name: String, ok: bool, detail: String) -> void:
	print("COMBAT %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	var cars: Array = scene.get("vehicles") if "vehicles" in scene else []
	if cars.is_empty():
		var traffic = scene.get_node_or_null("TrafficManager")
		cars = traffic.get("active_vehicles") if traffic != null else []
	if cars.is_empty():
		_check("vehicle_damage", false, "no cars")
		quit(); return
	var car = cars[0] as Node3D
	var h0: float = float(car.get("health"))
	var stage_before: int = int((car.get("combat") as RefCounted).get("stage"))
	for i in 8:
		car.call("take_weapon_damage", 25.0)
	var stage: int = int((car.get("combat") as RefCounted).get("stage"))
	_check("vehicle_damage", float(car.get("health")) < h0, "health %.0f -> %.0f" % [h0, float(car.get("health"))])
	_check("vehicle_explodes", bool(car.get("destroyed")), "destroyed=%s stage=%d" % [bool(car.get("destroyed")), stage])
	_check("wreck_exists", car.get_node_or_null("Wreck") != null, "wreck node present")
	await _frames(10)
	var cops = get_nodes_in_group("police")
	if cops.is_empty():
		cops = get_nodes_in_group("police_foot_patrol")
	if cops.is_empty():
		_check("police_damage", false, "no officers")
		quit(); return
	var cop = cops[0] as Node3D
	var ch0: float = float(cop.get("health"))
	cop.call("take_damage_at", 25.0, cop.global_position, 1.0, Vector3.FORWARD)
	_check("police_damage", float(cop.get("health")) < ch0, "health %.0f -> %.0f" % [ch0, float(cop.get("health"))])
	for i in 6:
		cop.call("take_damage_at", 25.0, cop.global_position, 1.0, Vector3.FORWARD)
	_check("police_death", bool(cop.get("is_dead")), "dead=%s in_patrol=%s" % [bool(cop.get("is_dead")), cop.is_in_group("police_foot_patrol")])
	quit()
