extends SceneTree

## Visual review of the gameplay overhaul.
## $env:SPLOOGE_SHOTS="overhaul_v"; Godot ... --script res://tests/overhaul_visual.gd

var scene: Node3D
var player: Node3D
var review: Camera3D
var shots := "overhaul_v"

func _initialize() -> void:
	var e = OS.get_environment("SPLOOGE_SHOTS")
	if not e.is_empty(): shots = e
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/" + shots))
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _capture(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://tests/%s/%s.png" % [shots, name])
	print("CAPTURED ", name)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	player = get_nodes_in_group("player")[0]
	if player.get("vehicle") != null:
		player.get("vehicle").call("exit_vehicle")
		await _frames(10)
	review = Camera3D.new()
	review.fov = 62.0
	scene.add_child(review)
	review.current = true
	await _frames(6)

	# Motorbike rider
	var vehicles: Array = scene.get("vehicles")
	var bike = null
	for v in vehicles:
		if v != null and bool(v.get("is_motorbike")): bike = v; break
	if bike != null:
		bike.call("enter", player)
		bike.set("speed", 10.0)
		await _frames(10)
		var p: Vector3 = bike.global_position
		review.global_position = p + Vector3(4.0, 2.2, 5.0)
		review.look_at(p + Vector3.UP * 1.0, Vector3.UP)
		await _capture("01_bike_rider")
		bike.set("speed", 0.0)
		bike.call("exit_vehicle")
		await _frames(10)

	# Skateboard
	player.call("toggle_skateboard")
	await _frames(20)
	var board = get_nodes_in_group("skateboards")[0]
	var bp: Vector3 = board.global_position
	review.global_position = bp + Vector3(3.2, 2.0, 3.8)
	review.look_at(bp + Vector3.UP * 0.9, Vector3.UP)
	await _capture("02_skateboard")
	player.call("toggle_skateboard")
	await _frames(10)

	# NOS distortion
	if bike != null:
		bike.call("enter", player)
		bike.set("speed", 30.0)
		bike.set("boost_on", true)
		await _frames(30)
		await _capture("04_nos_boost")
		bike.set("boost_on", false)
		bike.set("speed", 0.0)
		bike.call("exit_vehicle")
		await _frames(10)

	# Vehicle explosion
	if not vehicles.is_empty():
		var car = vehicles[0]
		for i in 8: car.call("take_weapon_damage", 30.0)
		await _frames(3)
		var ep: Vector3 = car.global_position
		review.global_position = ep + Vector3(7.0, 4.0, 9.0)
		review.look_at(ep + Vector3.UP, Vector3.UP)
		await _capture("03_explosion")
	quit()
