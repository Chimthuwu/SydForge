extends SceneTree

## Night capture of the new Kings Cross billboard anchor (L64 step).

func _initialize() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n: await process_frame

func _run() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(scene)
	await _frames(90)
	var tm = scene.get_node_or_null("WorldTimeManager")
	if tm != null:
		tm.set_time(22.0)
	await _frames(30)
	var camera := Camera3D.new()
	camera.fov = 60.0
	scene.add_child(camera)
	camera.make_current()
	# On Darlinghurst Road's centreline, looking east at the junction pylon.
	camera.global_position = Vector3(1452.0, 6.0, 53.5)
	camera.look_at(Vector3(1499.0, 11.0, 44.5), Vector3.UP)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/captures/l89/kings_cross_anchor_night.png")
	print("CAPTURED kings_cross_anchor_night")
	quit(0)
