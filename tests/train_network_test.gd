extends SceneTree

const CbdDistrictScript := preload("res://scripts/sydney_cbd_district.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func run() -> void:
	var scene: Node3D = CbdDistrictScript.new()
	root.add_child(scene)
	for _i in 30:
		await process_frame
	var trains = scene.get_node_or_null("TrainManager")
	check(trains != null, "TrainManager is active in the canonical scene")
	if trains == null:
		quit(1)
		return
	check(trains.trains.size() == 2, "two K Set consists run the corridor")
	var total_cars := 0
	for train: Dictionary in trains.trains:
		total_cars += (train["cars"] as Array).size()
	check(total_cars == 8, "eight K Set cars are present")
	var first_car: Node3D = (trains.trains[0]["cars"] as Array)[0]
	var first_pos: Vector3 = first_car.global_position
	check(first_pos.is_finite(), "train position is finite")
	for _i in 60:
		await process_frame
	var second_pos: Vector3 = first_car.global_position
	check(first_pos.distance_to(second_pos) > 0.5, "trains actually move along the route")
	var railway = scene.cbd_world.get_node_or_null("SydneyRailNetwork")
	check(railway != null and railway.station_nodes.size() == 5, "all five stations exist")
	for station_id in railway.station_nodes:
		check(railway.station_nodes[station_id].find_child("PlatformLevel", true, false) != null,
			"station has a platform level: " + station_id)
	var player = scene.get("player")
	check(player != null and player.vehicle != null, "game opens in a car on the bridge")
	check(absf((scene.get_node_or_null("WorldTimeManager")).current_time_hours - 11.0) < 0.2,
		"game opens at 11 AM")
	print("TRAIN STATS: ", trains.stats)
	print("RESULT: %d checks, %d failures" % [checks, failures])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
