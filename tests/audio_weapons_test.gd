extends SceneTree

## Focused verification for the overhaul's audio mix, weapon feel and engine
## audio state. Run with the bundled console executable:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##     --script res://tests/audio_weapons_test.gd

var audio: Node
var world: Node3D
var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)


func frames(count: int) -> void:
	for i in count:
		await physics_frame


func run() -> void:
	# The --script harness does not instantiate project autoloads, so create the
	# same singleton path the game uses.
	audio = root.get_node_or_null("AudioDirector")
	if audio == null:
		audio = load("res://scripts/audio_manager.gd").new()
		audio.name = "AudioDirector"
		root.add_child(audio)
	await process_frame

	check(AudioServer.get_bus_index("Weapons") != -1, "Weapons bus exists")
	check(AudioServer.get_bus_index("Vehicles") != -1, "Vehicles bus exists")
	check(AudioServer.get_bus_index("Environment") != -1, "Environment bus exists")
	check(AudioServer.get_bus_effect_count(0) >= 1, "Master has a protective limiter")
	check(audio.bus_volume("Weapons") < -2.0, "Weapons bus has headroom below 0 dB")
	check(audio.weapon_peak("pistol") <= 0.65, "pistol sample peak is controlled")
	check(audio.weapon_peak("smg") <= 0.55, "SMG sample peak is controlled")
	check(audio.weapon_peak("shotgun") <= 0.70, "shotgun sample peak is controlled")

	world = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	await frames(40)
	var p: BoomPlayer = world.player

	# Automatic fire must not create unbounded players or duplicate reports.
	for i in 40:
		world.gunshot("smg")
		await process_frame
	check(audio.active_weapon_voices() <= 3, "rapid fire stays inside the pooled voice cap")

	# SMG identity: 30-round magazine, automatic cadence, reload restores it.
	p.equip_weapon(BoomPlayer.WEAPON_SMG)
	await frames(12)
	check(p.is_smg_equipped(), "SMG can be equipped")
	p.smg_ammo = 30
	p.weapon_switch_time = 0.0
	p.fire_time = 0.0
	p.shoot()
	check(p.smg_ammo == 29, "SMG spends one round per shot")
	check(p.weapon_status_text().contains("SMG"), "HUD weapon status reports the SMG")
	p.smg_ammo = 0
	p.smg_reload_time = 0.0
	p.reload()
	check(p.smg_reload_time > 0.0, "empty SMG starts a reload")
	p.smg_reload_time = 0.01
	await frames(3)
	check(p.smg_ammo == 30, "SMG reload refills the magazine")

	# Movement envelope: sprint is materially faster than walking.
	p.equip_weapon(BoomPlayer.WEAPON_PISTOL)
	p.global_position = Vector3(0, 0.2, 45)
	p.velocity = Vector3.ZERO
	await frames(5)
	var walk_start := p.global_position
	Input.action_press("forward")
	await frames(60)
	Input.action_release("forward")
	var walk_distance := walk_start.distance_to(p.global_position)
	p.velocity = Vector3.ZERO
	var sprint_start := p.global_position
	Input.action_press("forward")
	Input.action_press("sprint")
	await frames(60)
	Input.action_release("forward")
	Input.action_release("sprint")
	var sprint_distance := sprint_start.distance_to(p.global_position)
	check(sprint_distance > walk_distance + 3.0, "sprint is substantially faster than walking")

	# Engine audio follows state and stays below the weapon mix.
	var car: ArcadeCar = world.vehicles[0]
	car.global_position = Vector3(0, 0.1, 45)
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	p.global_position = Vector3(2.5, 0.1, 45)
	await frames(5)
	world.interact()
	check(p.vehicle == car, "enters car for engine audio test")
	Input.action_press("forward")
	await frames(60)
	Input.action_release("forward")
	check(car.engine_audio_system != null, "vehicle has an EngineAudio system")
	if car.engine_audio_system != null:
		check(car.engine_audio_system.engine_rpm > 0.2, "engine RPM rises with speed")
		check(car.engine_audio_system.engine.volume_db < -8.0, "engine stays at a controlled level")
		check(car.engine_audio_system.engine.pitch_scale > 0.9, "engine pitch follows RPM")
	var low_gear := EngineAudio.gear_rpm(5.0, 32.0)
	var next_gear := EngineAudio.gear_rpm(8.0, 32.0)
	check(next_gear < low_gear, "gear model drops RPM at a shift")
	check(EngineAudio.profile_for_class(VehicleVisualBuilder.VehicleClass.BUS) == "bus", "bus uses a bus engine profile")
	check(EngineAudio.profile_for_class(VehicleVisualBuilder.VehicleClass.MOTORBIKE) == "motorbike", "motorbike uses its own profile")

	# Weapon switching is immediate and does not strand the player unarmed.
	car.speed = 0.0
	car.velocity = Vector3.ZERO
	await frames(3)
	car.exit_vehicle()
	await frames(3)
	p.equip_weapon(BoomPlayer.WEAPON_SHOTGUN)
	check(p.is_shotgun_equipped(), "switch to shotgun succeeds")
	p.equip_weapon(BoomPlayer.WEAPON_SMG)
	check(p.is_smg_equipped(), "switch back to SMG succeeds")
	p.cycle_weapon()
	check(not p.is_smg_equipped(), "cycle moves to the next weapon")

	print("RESULT: %d checks, %d failures" % [checks, failures])
	world.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
