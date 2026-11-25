extends SceneTree

## Wanted-system regression: threshold escalation, the officer-down chain
## (heat -> nearby unit alert), spawn caps, decay and clear. Exercises
## WantedSystem with a plain Node3D player (headless harness setup).

const WantedSystemScript := preload("res://scripts/wanted_system.gd")

var checks := 0
var failures := 0
var signal_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok:
		failures += 1

func run() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var wanted := WantedSystemScript.new()
	wanted.name = "WantedSystem"
	wanted.add_to_group("wanted_system")
	root.add_child(wanted)
	wanted.setup(player)

	wanted.wanted_changed.connect(func(_stars: int) -> void: signal_count += 1)

	# --- Baseline and proportional escalation (thresholds: 18/38/60/82/96) ---
	check(wanted.stars == 0 and wanted.stars_text() == "", "starts at zero stars")
	wanted.add_crime(10.0, "test")
	check(wanted.stars == 0 and wanted.heat == 10.0, "minor crime (heat 10) stays below one star")
	wanted.add_crime(10.0)
	check(wanted.stars == 1 and wanted.stars_text().contains("★"), "heat 20 crosses threshold 1, HUD text shown")
	wanted.add_crime(20.0)
	check(wanted.stars == 2, "heat 40 crosses threshold 2")
	wanted.add_crime(20.0)
	check(wanted.stars == 3, "heat 60 crosses threshold 3")
	check(signal_count == 3, "wanted_changed emitted once per star increase")

	# --- Officer-down chain: heat jump + alert to nearby units ---
	wanted.officer_killed(Vector3(37.0, 0.0, -11.0))
	check(wanted.heat == 82.0 and wanted.stars == 4, "officer_killed adds 22 heat and escalates to tier 4")
	wanted.add_crime(50.0)
	check(wanted.heat == 100.0 and wanted.stars == 5, "heat capped at 100, stars capped at 5")

	# --- Police spawn for the wanted level ---
	wanted._spawn_timer = 0.05
	for _i in 10:
		await process_frame
	check(wanted.police.size() == 1, "police unit spawns for the wanted level")
	if wanted.police.size() > 0:
		var car: Node3D = wanted.police[0]
		check(car.get("target") == player, "spawned unit pursues the player")
		var spawn_dist: float = car.global_position.distance_to(player.global_position)
		check(spawn_dist >= 100.0 and spawn_dist <= 190.0, "unit spawns out of immediate sight range")

		# --- Alert reaction: the officer-down ping reaches a live unit ---
		var alert_pos := Vector3(37.0, 0.0, -11.0)
		var alert_signals := signal_count
		wanted.officer_killed(alert_pos)
		check(car.get("_has_last_seen") == true, "nearby unit reacts to officer-down alert")
		var perceived: Vector3 = car.get("_perceived_target")
		check(perceived.distance_to(alert_pos + Vector3.UP) < 0.05, "alerted unit converges on the death position")
		check(car.get("_lost_sight_time") == 0.0 and car.get("_reaction_delay") <= 0.15, "alert resets tracking and reaction delay")
		check(wanted.heat == 100.0 and signal_count == alert_signals, "alert at max heat re-escalates nothing")

	# --- Escapable: heat decays when contact is clearly broken ---
	if wanted.police.size() > 0:
		wanted.police[0].global_position = Vector3(500.0, 1.0, 500.0)
	wanted.cooldown = 0.0
	var heat_before: float = wanted.heat
	for _i in 90:
		await process_frame
	check(wanted.heat < heat_before, "heat decays once contact is broken and cooldown ends")

	# --- Clear ---
	wanted.clear()
	check(wanted.stars == 0 and wanted.heat == 0.0 and wanted.police.is_empty(), "clearing wanted removes heat and police")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
