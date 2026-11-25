extends SceneTree

## Headless wheelie rider-pose coverage (L53 bounded step). Complements
## docs/WHEELIE_RIDER_POSE_TESTPLAN.md: pose tracking, sustain through
## steering, gradual brake release, NOS coexistence, and no wheelie on a
## wreck. Visual framing/lean aesthetics stay with the live test plan.

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
	print("WHEELIE %s %s | %s" % ["PASS" if ok else "FAIL", name, detail])

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	player = scene.get_node_or_null("Player")
	if player == null:
		var ps = get_nodes_in_group("player")
		player = ps[0] if not ps.is_empty() else null
	var bike = null
	var vehicles: Array = scene.get("vehicles") if "vehicles" in scene else []
	for v in vehicles:
		if v != null and bool(v.get("is_motorbike")):
			bike = v
			break
	_check("motorbike_exists", bike != null, "")
	if bike == null:
		_finish()
		return

	bike.call("enter", player)
	await _frames(6)
	var rider: Node3D = bike.get_node_or_null("BodyArt/Rider")
	var front: Node3D = bike.get("front_wheel_visual")
	_check("rider_present", rider != null, "")
	_check("front_wheel_present", front != null, "")

	# 1. Wheelie engages and the rider pose tracks the factor.
	bike.set("speed", 24.0)
	Input.action_press("wheelie")
	await _frames(30)
	var w: float = bike.get("wheelie")
	_check("wheelie_engages", w > 0.2, "factor=%.2f" % w)
	if rider != null:
		_check("rider_leans_back", rider.rotation.x < 0.0, "rot.x=%.3f" % rider.rotation.x)
		_check("rider_pose_tracks", absf(rider.rotation.x - (-w * 0.22)) < 0.01,
			"rot.x=%.3f expect=%.3f" % [rider.rotation.x, -w * 0.22])
	if front != null:
		_check("front_wheel_lifts", absf(front.position.y - (0.42 + w * 0.45)) < 0.01,
			"y=%.3f expect=%.3f" % [front.position.y, 0.42 + w * 0.45])

	# 2. Steering through the turn sustains the wheelie (only crash tips or
	# low speed cancel it) and the rider pose stays tied to the factor.
	var w_before: float = bike.get("wheelie")
	Input.action_press("left")
	await _frames(20)
	Input.action_release("left")
	var w_turn: float = bike.get("wheelie")
	_check("wheelie_sustains_through_turn", w_turn > 0.2 and w_turn >= w_before - 0.05,
		"before=%.2f after=%.2f" % [w_before, w_turn])
	if rider != null:
		_check("rider_pose_tracks_turn", absf(rider.rotation.x - (-w_turn * 0.22)) < 0.01,
			"rot.x=%.3f expect=%.3f" % [rider.rotation.x, -w_turn * 0.22])

	# 3. Braking lowers the front gradually: factor decays over frames and the
	# rider returns to neutral instead of snapping.
	Input.action_press("back")
	bike.set("speed", 12.0)
	await _frames(20)
	var w_mid: float = bike.get("wheelie")
	_check("brake_lowers_wheelie", w_mid < w_turn, "mid=%.2f peak=%.2f" % [w_mid, w_turn])
	await _frames(80)
	Input.action_release("back")
	var w_end: float = bike.get("wheelie")
	_check("wheelie_fully_released", w_end == 0.0, "factor=%.2f" % w_end)
	if rider != null:
		_check("rider_returns_neutral", rider.rotation.x == 0.0, "rot.x=%.3f" % rider.rotation.x)
	if front != null:
		_check("front_wheel_lowered", absf(front.position.y - 0.42) < 0.01,
			"y=%.3f" % front.position.y)
	Input.action_release("wheelie")

	# 4. NOS and wheelie coexist (boost held via its real input action).
	Input.action_press("sprint")
	bike.set("speed", 24.0)
	Input.action_press("wheelie")
	await _frames(30)
	var w_nos: float = bike.get("wheelie")
	_check("wheelie_with_nos", bool(bike.get("boost_on")) and w_nos > 0.2, "boost=%s factor=%.2f" % [bike.get("boost_on"), w_nos])
	Input.action_release("wheelie")
	Input.action_release("sprint")
	bike.set("speed", 0.0)
	await _frames(10)

	# 5. A wreck cannot wheelie: destroyed freezes the wheelie machinery.
	bike.call("take_damage", 9999.0)
	await _frames(5)
	var wrecked: bool = bool(bike.get("destroyed"))
	var w_wreck: float = bike.get("wheelie")
	bike.set("speed", 24.0)
	Input.action_press("wheelie")
	await _frames(20)
	Input.action_release("wheelie")
	bike.set("speed", 0.0)
	_check("wreck_state", wrecked, "destroyed=%s" % wrecked)
	_check("no_wheelie_on_wreck", bool(bike.get("destroyed")) and float(bike.get("wheelie")) <= w_wreck + 0.001,
		"before=%.2f after=%.2f" % [w_wreck, bike.get("wheelie")])

	_finish()

func _finish() -> void:
	print("RESULT: %d checks, %d failures" % [pass_count, fail_count])
	quit(1 if fail_count else 0)
