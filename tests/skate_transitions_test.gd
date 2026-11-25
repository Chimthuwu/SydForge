extends SceneTree

## L51 bounded step: the shared integration scenarios that were still
## unmechanised headless — ollie + kickturn, entering a vehicle while the
## skateboard is mounted (board must dismount cleanly), auto headlights on
## a night entry, and exiting back to walking. Grind/wheelie/explosion/police
## chains live in their own suites.

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
	print("SKATE %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	player = scene.get_node_or_null("Player")
	if player == null:
		var ps = get_nodes_in_group("player")
		player = ps[0] if not ps.is_empty() else null
	_check("player", player != null, "")
	if player == null:
		_finish()
		return
	var start_car = player.get("vehicle")
	if start_car != null:
		start_car.call("exit_vehicle")
		await _frames(10)
	_check("starts_on_foot", player.get("vehicle") == null, "")

	# Night: the board and the night-entry headlight test need it dark.
	var tm = scene.get_node_or_null("WorldTimeManager")
	if tm != null:
		tm.set_time(22.0)
	await _frames(10)

	# --- Mount + ollie + kickturn ---
	player.call("toggle_skateboard")
	await _frames(8)
	var boards = get_nodes_in_group("skateboards")
	var board: Node3D = boards[0] if not boards.is_empty() else null
	_check("board_mounted", board != null and player.has_meta("skateboard"), "")
	if board == null:
		_finish()
		return
	await _frames(10)  # settle on the ground
	board.set("_jump_buffer", 0.12)
	await _frames(6)
	_check("ollie_launches", bool(board.get("airborne")) and bool(board.get("ollie")),
		"airborne=%s ollie=%s" % [board.get("airborne"), board.get("ollie")])
	Input.action_press("left")
	await _frames(4)
	Input.action_release("left")
	_check("kickturn_tricks", board.get("trick_name") == "KICKTURN" and float(board.get("trick_spin")) != 0.0,
		"trick=%s spin=%.2f" % [board.get("trick_name"), board.get("trick_spin")])
	await _frames(40)  # land

	# --- Enter a vehicle while the skateboard is mounted ---
	var car = null
	var vehicles: Array = scene.get("vehicles") if "vehicles" in scene else []
	var best := INF
	for v in vehicles:
		if v == null or not is_instance_valid(v) or bool(v.get("is_motorbike")):
			continue
		if v.get("driver") != null:
			continue
		var d: float = v.global_position.distance_to(player.global_position)
		if d < best:
			best = d
			car = v
	_check("vehicle_nearby", car != null, "dist=%.1f" % best)
	if car != null:
		var entered: bool = bool(car.call("enter", player))
		await _frames(4)
		_check("enter_from_board", entered and player.get("vehicle") == car, "entered=%s" % entered)
		_check("board_dismounts_on_enter", not player.has_meta("skateboard") and get_nodes_in_group("skateboards").is_empty(),
			"meta=%s boards=%d" % [player.has_meta("skateboard"), get_nodes_in_group("skateboards").size()])
		_check("night_entry_auto_headlights", bool(car.get("headlights_on")), "headlights_on=%s" % car.get("headlights_on"))

		# --- Exit back to walking ---
		car.set("speed", 0.0)
		await _frames(6)
		var exited: bool = bool(car.call("exit_vehicle"))
		await _frames(4)
		_check("exit_to_walking", exited and player.get("vehicle") == null and player.visible,
			"exited=%s visible=%s" % [exited, player.visible])
		_check("exit_lights_off", not bool(car.get("headlights_on")), "headlights_on=%s" % car.get("headlights_on"))

	_finish()

func _finish() -> void:
	print("RESULT: %d checks, %d failures" % [pass_count, fail_count])
	quit(1 if fail_count else 0)
