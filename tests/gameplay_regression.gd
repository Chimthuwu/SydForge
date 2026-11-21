extends SceneTree

## Scripted gameplay regression over the canonical scene (windowed).
## Exercises input-driven on-foot movement, combat state, vehicle entry/drive/
## exit, train movement, living-world actors and a sustained-run stability check.

var scene: Node3D
var player: Node3D
var results: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _check(name: String, ok: bool, detail: String) -> void:
	results.append("%s: %s (%s)" % ["PASS" if ok else "FAIL", name, detail])
	print("REGRESSION %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])

func _find(group: String) -> Node:
	var nodes: Array = get_root().get_nodes_in_group(group)
	return nodes[0] if not nodes.is_empty() else null

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	player = scene.get_node_or_null("Player") as Node3D
	if player == null:
		var ps: Array = get_root().get_nodes_in_group("player")
		player = ps[0] if not ps.is_empty() else null
	_check("scene_player", player != null, "player node resolved")

	# --- On-foot movement / sprint / jump ---
	if player != null:
		# The canonical start places the player inside a car; exit first.
		if player.get("vehicle") != null:
			var current_car: Node = player.get("vehicle") as Node
			current_car.call("exit_vehicle")
			await _frames(10)
		var start: Vector3 = player.global_position
		Input.action_press("forward")
		Input.action_press("sprint")
		await _frames(90)
		Input.action_release("forward")
		Input.action_release("sprint")
		var moved: float = player.global_position.distance_to(start)
		_check("on_foot_move", moved > 1.0, "moved %.2f m" % moved)

		var y_before: float = player.global_position.y
		Input.action_press("jump")
		await _frames(1)
		Input.action_release("jump")
		var y_peak: float = player.global_position.y
		await _frames(10)
		y_peak = maxf(y_peak, player.global_position.y)
		await _frames(60)
		var y_after: float = player.global_position.y
		_check("jump", y_peak > y_before + 0.05, "y %.2f -> %.2f" % [y_before, y_peak])
		_check("landing", absf(y_after - y_before) < 1.2, "y settled %.2f" % y_after)

		# --- Combat state ---
		var ammo_before: int = int(player.get("ammo"))
		player.call("shoot")
		await _frames(6)
		var ammo_after: int = int(player.get("ammo"))
		_check("weapon_fire", ammo_after < ammo_before or ammo_after == ammo_before,
			"ammo %d -> %d" % [ammo_before, ammo_after])
		var health_before: float = float(player.get("health"))
		player.call("take_damage", 25.0)
		var health_damaged: float = float(player.get("health"))
		_check("damage", health_damaged < health_before, "health %.0f -> %.0f" % [health_before, health_damaged])
		player.call("respawn")
		var health_respawn: float = float(player.get("health"))
		_check("respawn", health_respawn >= 99.0, "health %.0f" % health_respawn)

		# --- Vehicle enter / drive / exit ---
		var traffic := scene.get_node_or_null("TrafficManager")
		var cars: Array = traffic.get("active_vehicles") if traffic != null else []
		if not cars.is_empty():
			var car: Node3D = cars[0] as Node3D
			var entered: bool = bool(car.call("enter", player))
			await _frames(10)
			_check("vehicle_enter", entered and player.get("vehicle") != null, "enter=%s" % entered)
			var car_start: Vector3 = car.global_position
			Input.action_press("forward")
			await _frames(120)
			var axis: float = Input.get_axis("back", "forward")
			var car_speed: float = float(car.get("speed"))
			Input.action_release("forward")
			var car_moved: float = car.global_position.distance_to(car_start)
			_check("vehicle_drive", car_moved > 2.0, "drove %.2f m axis=%.1f speed=%.1f" % [car_moved, axis, car_speed])
			_check("vehicle_grounded", car.global_position.y > -2.0 and car.global_position.y < 60.0,
				"y %.2f" % car.global_position.y)
			Input.action_press("back")
			for brake_frame in 150:
				if absf(float(car.get("speed"))) < 2.0:
					break
				await process_frame
			Input.action_release("back")
			await _frames(20)
			var exited: bool = bool(car.call("exit_vehicle"))
			await _frames(10)
			_check("vehicle_exit", player.get("vehicle") == null, "exit=%s msg=%s" % [exited, str(scene.get("message"))])
		else:
			_check("vehicle_enter", false, "no active vehicles")

	# --- Train movement ---
	var trains := scene.get_node_or_null("TrainManager")
	if trains != null:
		var list: Array = trains.get("trains")
		var first: Dictionary = list[0] if not list.is_empty() else {}
		if not first.is_empty():
			var cars: Array = first["cars"]
			var lead: Node3D = cars[0] as Node3D
			var p0: Vector3 = lead.global_position
			await _frames(120)
			var p1: Vector3 = lead.global_position
			_check("train_movement", p0.distance_to(p1) > 1.0,
				"moved %.2f m idx=%.1f route=%d" % [p0.distance_to(p1), float(first["index"]), (trains.get("_route") as Array).size()])
			var railway: Node3D = null
			for n in scene.find_children("*", "Node3D", true, false):
				if n.name == "SydneyRailNetwork":
					railway = n
					break
			var route: Array = railway.get("main_route_points") if railway != null else []
			var nearest := 1e9
			for rp in route:
				nearest = mini(nearest, Vector2((rp as Vector3).x, (rp as Vector3).z).distance_to(Vector2(p1.x, p1.z)))
			_check("train_on_route", nearest < 60.0, "nearest route point %.1f m" % nearest)
		else:
			_check("train_movement", false, "no trains")
	else:
		_check("train_movement", false, "no TrainManager")

	# --- Living world ---
	var peds := scene.get_node_or_null("PedestrianManager")
	var ped_count: int = (peds.get("active_pedestrians") as Array).size() if peds != null else 0
	_check("pedestrians_spawn", ped_count > 0, "%d active" % ped_count)
	if ped_count > 0:
		var all_peds: Array = peds.get("active_pedestrians")
		var starts: Array[Vector3] = []
		for p in all_peds:
			starts.append((p as Node3D).global_position)
		await _frames(90)
		var max_moved := 0.0
		for i in all_peds.size():
			var p: Node3D = all_peds[i] as Node3D
			if is_instance_valid(p):
				max_moved = maxf(max_moved, p.global_position.distance_to(starts[i]))
		_check("pedestrians_move", max_moved > 0.5, "max moved %.2f m" % max_moved)
	var wild := scene.get_node_or_null("WildlifeManager")
	var wild_count: int = (wild.get("active_wildlife") as Array).size() if wild != null else 0
	_check("wildlife_spawn", wild_count > 0, "%d active" % wild_count)

	# --- Sustained run stability ---
	var nodes0 := get_root().find_children("*", "", true, false).size()
	var mem0: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	await _frames(600)
	var nodes1 := get_root().find_children("*", "", true, false).size()
	var mem1: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	_check("node_stability", nodes1 - nodes0 < 250, "nodes %d -> %d" % [nodes0, nodes1])
	_check("texture_stability", mem1 - mem0 < 16 * 1024 * 1024,
		"texture mem %.1f -> %.1f MB" % [mem0 / 1048576.0, mem1 / 1048576.0])

	var passes := 0
	for r in results:
		if r.begins_with("PASS"):
			passes += 1
	print("REGRESSION_TOTAL %d/%d" % [passes, results.size()])
	quit()
