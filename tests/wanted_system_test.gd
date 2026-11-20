extends SceneTree

const WantedSystemScript := preload("res://scripts/wanted_system.gd")

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
	var player := Node3D.new()
	root.add_child(player)
	var wanted := WantedSystemScript.new()
	wanted.name = "WantedSystem"
	wanted.add_to_group("wanted_system")
	root.add_child(wanted)
	wanted.setup(player)
	check(wanted.stars == 0 and wanted.stars_text() == "", "starts at zero stars")
	wanted.add_crime(10.0, "test")
	check(wanted.stars == 1, "first crime raises one star")
	wanted.add_crime(20.0)
	check(wanted.stars >= 2 and wanted.stars_text().contains("★"), "more crime raises stars and HUD text")
	for _i in 60:
		await process_frame
	check(wanted.police.size() >= 2, "police spawn for the wanted level")
	var police = wanted.police[0]
	var first: Vector3 = police.global_position
	await process_frame
	await process_frame
	check(first.distance_to(police.global_position) >= 0.0, "police car is active")
	wanted.clear()
	check(wanted.stars == 0 and wanted.police.is_empty(), "clearing wanted removes police")
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
