extends SceneTree

## NPC/human-character review captures.
##   $env:SPLOOGE_SHOTS="npc_after"; Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1600x900 --script res://tests/npc_views.gd

var scene: Node3D
var review: Camera3D
var shots := "npc_after"


func _initialize() -> void:
	var env := OS.get_environment("SPLOOGE_SHOTS")
	if not env.is_empty():
		shots = env
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/" + shots))
	call_deferred("run")


func _settle(count: int) -> void:
	for i in count:
		await process_frame


func _capture(file: String, label: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/%s/%s.png" % [shots, file])
	print("CAPTURED: ", label, " -> ", file)


func _look(from: Vector3, at: Vector3) -> void:
	review.global_position = from
	if from.distance_to(at) > 0.1:
		review.look_at(at, Vector3.UP)


func _move_player(x: float, z: float, yaw: float = 0.0) -> void:
	if scene.player != null:
		scene.player.global_position = Vector3(x, 0.35, z)
		scene.player.rotation.y = yaw
		if scene.player.vehicle != null:
			scene.player.vehicle.global_position = Vector3(x, 0.5, z)
	await _settle(80)


func _get_pedestrians() -> Array:
	var peds: Node = scene.get_node_or_null("PedestrianManager")
	if peds == null:
		return []
	return peds.get("active_pedestrians")


func _capture_ped_closeup(prefix: String) -> void:
	var list := _get_pedestrians()
	var target = null
	for p in list:
		if is_instance_valid(p):
			target = p
			break
	if target == null:
		print("NO PEDESTRIANS for ", prefix)
		return
	var pos: Vector3 = target.global_position
	var fwd: Vector3 = -target.global_transform.basis.z
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	_look(pos + fwd * 2.3 + side * 0.6 + Vector3.UP * 1.45, pos + Vector3.UP * 1.15)
	await _capture(prefix + "_close", "pedestrian close-up")
	_look(pos + side * 4.0 - fwd * 1.2 + Vector3.UP * 1.7, pos + Vector3.UP * 1.1)
	await _capture(prefix + "_group", "pedestrian group view")


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(70)
	var time_manager := scene.get_node_or_null("WorldTimeManager")
	if time_manager != null:
		time_manager.set_time(13.5)
	await _settle(20)

	review = Camera3D.new()
	review.fov = 65.0
	review.far = 3000.0
	review.near = 0.05
	scene.add_child(review)
	review.current = true
	await _settle(6)

	# CBD daytime pedestrians.
	await _move_player(-80.0, -120.0, 0.0)
	await _capture_ped_closeup("01_cbd")

	# Hyde Park daytime.
	await _move_player(448.0, -330.0, 0.0)
	await _capture_ped_closeup("02_hyde")

	# Kings Cross evening/night (nightlife, sex workers, drug-affected presence).
	if time_manager != null:
		time_manager.set_time(22.5)
	await _settle(40)
	await _move_player(1508.0, 66.0, 0.0)
	await _capture_ped_closeup("03_kings_cross_night")
	_look(Vector3(1508.0, 2.2, 82.0), Vector3(1508.0, 1.2, 55.0))
	await _capture("03_kings_cross_street", "Kings Cross night street")

	# Circular Quay.
	if time_manager != null:
		time_manager.set_time(14.0)
	await _settle(30)
	await _move_player(220.0, -1290.0, 0.0)
	_look(Vector3(220.0, 2.0, -1270.0), Vector3(220.0, 1.2, -1305.0))
	await _capture("04_circular_quay", "Circular Quay pedestrians")

	print("NPC_ACTIVE=", _get_pedestrians().size())
	scene.queue_free()
	await process_frame
	quit()
