extends SceneTree

## Grind entry on REAL city geometry (L55 bounded step). The unit tests mount
## and tick the grind state machine by hand; this one boots the full world,
## probes the documented grindable locations from
## docs/GRIND_CITY_LEDGES_TESTPLAN.md with a downward ray, ollies onto the
## probed surface and requires the board's own raycast entry, sustain and
## jump exit to work against that geometry. Visual rail alignment, sparks
## and camera framing stay with the live sign-off matrix.

var scene: Node3D
var player: Node3D
var pass_count := 0
var fail_count := 0

const LOCATIONS := [
	["circular_quay_seawall", Vector2(200, -1500)],
	["the_rocks_coping", Vector2(100, -1400)],
	["central_platform_edges", Vector2(-40, -460)],
	["darling_harbour_rails", Vector2(-200, -800)],
	["barangaroo_ledges", Vector2(-300, -600)],
	["george_st_furniture", Vector2(0, -500)],
	["parramatta_rd_median", Vector2(-3200, 300)],
]

func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _check(name: String, ok: bool, detail: String) -> void:
	if ok: pass_count += 1
	else: fail_count += 1
	print("GRIND %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])

func _probe_top(xz: Vector2) -> Dictionary:
	## Top grind-eligible surface near (x, z): a downward ray from above roof
	## height whose first hit faces up. Tries small offsets so a prop or
	## awning at the exact point cannot shadow the ledge.
	var space := player.get_world_3d().direct_space_state
	for offset in [Vector2.ZERO, Vector2(1.2, 0), Vector2(-1.2, 0), Vector2(0, 1.2), Vector2(0, -1.2)]:
		var from := Vector3(xz.x + offset.x, 120.0, xz.y + offset.y)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 200.0)
		var hits: Dictionary = space.intersect_ray(query)
		if hits.is_empty():
			continue
		if float(hits.get("normal", Vector3.UP).y) >= 0.65:
			return hits
	return {}

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

	# Canonical default spawns the player inside a car; the skateboard needs
	# them on foot (same as the gameplay_overhaul harness).
	if player.get("vehicle") != null:
		player.get("vehicle").call("exit_vehicle")
		await _frames(10)

	var boards = get_nodes_in_group("skateboards")
	player.call("toggle_skateboard")
	await _frames(6)
	boards = get_nodes_in_group("skateboards")
	var board: Node3D = boards[0] if not boards.is_empty() else null
	_check("board_mounted", board != null and player.has_meta("skateboard"), "")
	if board == null:
		_finish()
		return

	var entered := 0
	var sustained := 0
	var exited := 0
	var probed := 0
	for loc in LOCATIONS:
		var top := _probe_top(loc[1])
		if top.is_empty() or float(top.get("normal", Vector3.UP).y) < 0.65:
			print("GRIND NOTE %s | no grind-eligible surface probed" % loc[0])
			continue
		probed += 1
		var surface_y: float = float(top["position"].y)
		# The board carries the driver, so teleport the BOARD (the player
		# follows on the next physics tick, not the other way round).
		board.global_position = Vector3(loc[1].x, surface_y + 0.6, loc[1].y)
		board.set("velocity", Vector3.ZERO)
		await _frames(12)  # board settles on the surface
		board.set("speed", 8.0)
		# Ollie: action_press() edge events do not reach is_action_just_pressed
		# in _physics_process from a SceneTree script, so seed the same jump
		# buffer the real "jump" press sets.
		board.set("_jump_buffer", 0.12)
		var got_it := false
		for _i in 90:
			await process_frame
			if bool(board.get("grinding")):
				got_it = true
				break
		if got_it:
			entered += 1
			var stable: float = board.get("_grind_stable")
			await _frames(30)
			var still: bool = bool(board.get("grinding"))
			if still:
				sustained += 1
			print("GRIND NOTE %s | entry ok surface_y=%.2f stable=%.2f sustained=%s" % [loc[0], surface_y, stable, still])
			# Manual exit via jump buffer.
			board.set("_jump_buffer", 0.12)
			await _frames(6)
			if not bool(board.get("grinding")):
				exited += 1
		else:
			print("GRIND NOTE %s | no entry from surface_y=%.2f" % [loc[0], surface_y])
		await _frames(6)

	print("GRIND NOTE summary | probed=%d entered=%d sustained=%d exited=%d" % [probed, entered, sustained, exited])
	_check("real_geometry_entry", probed >= 4 and entered >= 3, "probed=%d entered=%d" % [probed, entered])
	_check("grind_sustains_on_geometry", sustained >= 2, "sustained=%d" % sustained)
	_check("manual_exit_works", exited >= 1, "exited=%d" % exited)

	_finish()

func _finish() -> void:
	print("RESULT: %d checks, %d failures" % [pass_count, fail_count])
	quit(1 if fail_count else 0)
