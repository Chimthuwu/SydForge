extends SceneTree

var scene: Node3D
var player: Node3D
var pass_count := 0
var fail_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _check(name: String, ok: bool, detail: String) -> void:
	if ok: pass_count += 1
	else: fail_count += 1
	print("OVERHAUL %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	player = scene.get_node_or_null("Player")
	if player == null:
		var ps = get_nodes_in_group("player")
		player = ps[0] if not ps.is_empty() else null
	_check("player", player != null, "resolved")
	if player != null and player.get("vehicle") != null:
		var start_car = player.get("vehicle")
		start_car.call("exit_vehicle")
		await _frames(10)

	# Traffic variety and speed
	var tm = scene.get_node_or_null("TrafficManager")
	if tm != null:
		var classes := {}
		for i in 1200:
			var c: int = int(tm.call("_pick_vehicle_class", i % 2 == 0))
			classes[c] = true
		var unique := classes.size()
		_check("traffic_variety", unique >= 10, "%d distinct vehicle classes" % unique)
		var VVB = preload("res://sydney/ecosystem/vehicle_visual_builder.gd")
		var sports: float = float(VVB.get_class_specs(1).get("max_speed", 0.0))
		var supercar: float = float(VVB.get_class_specs(16).get("max_speed", 0.0))
		var sedan: float = float(VVB.get_class_specs(0).get("max_speed", 0.0))
		_check("vehicle_speeds", supercar > sports and sports > sedan, "supercar=%.0f sports=%.0f sedan=%.0f" % [supercar, sports, sedan])
	else:
		_check("traffic_variety", false, "no TrafficManager")

	# Skateboard toggle
	var board_count0 = get_nodes_in_group("skateboards").size()
	player.call("toggle_skateboard")
	await _frames(6)
	var boards = get_nodes_in_group("skateboards")
	var mounted = player.has_meta("skateboard")
	_check("skate_mount", boards.size() == board_count0 + 1 and mounted, "boards=%d mounted=%s" % [boards.size(), mounted])
	player.call("toggle_skateboard")
	await _frames(6)
	_check("skate_dismount", get_nodes_in_group("skateboards").size() == board_count0 and not player.has_meta("skateboard"), "boards=%d" % get_nodes_in_group("skateboards").size())

	# Motorbike rider + wheelie
	var vehicles: Array = scene.get("vehicles") if "vehicles" in scene else []
	var bike = null
	for v in vehicles:
		if v != null and bool(v.get("is_motorbike")):
			bike = v
			break
	_check("motorbike_exists", bike != null, "found=%s" % (bike != null))
	if bike != null:
		bike.call("enter", player)
		await _frames(6)
		_check("bike_rider", bike.get_node_or_null("BodyArt/Rider") != null, "rider present")
		bike.set("speed", 20.0)
		Input.action_press("wheelie")
		await _frames(30)
		var w: float = float(bike.get("wheelie"))
		Input.action_release("wheelie")
		_check("bike_wheelie", w > 0.2, "wheelie=%.2f" % w)
		await _frames(40)
		_check("bike_wheelie_release", float(bike.get("wheelie")) < w, "returned=%.2f" % float(bike.get("wheelie")))
		bike.call("exit_vehicle")
		await _frames(6)

	# Explosion AOE falloff
	var cars: Array = vehicles
	if not cars.is_empty():
		var car = cars[0]
		var before: float = float(car.get("health"))
		car.call("take_explosion_damage", 20.0)
		var after: float = float(car.get("health"))
		_check("explosion_damage", after < before, "health %.0f -> %.0f" % [before, after])

	# NOS overlay activation + cleanup
	var overlay = scene.get_node_or_null("NOSOverlay")
	_check("nos_overlay_exists", overlay != null, "present")
	if overlay != null and bike != null:
		bike.call("enter", player)
		bike.set("boost_on", true)
		bike.set("speed", 25.0)
		await _frames(20)
		var active: float = float(overlay.get("current"))
		bike.set("boost_on", false)
		bike.set("speed", 0.0)
		await _frames(90)
		var idle: float = float(overlay.get("current"))
		_check("nos_activation", active > 0.2, "intensity=%.2f" % active)
		_check("nos_cleanup", idle < 0.05, "intensity=%.2f" % idle)
		bike.call("exit_vehicle")

	print("OVERHAUL_TOTAL %d/%d" % [pass_count, pass_count + fail_count])
	quit()
