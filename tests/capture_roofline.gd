extends SceneTree

## Night skyline capture for the roofline dressing pass (L63 step).

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
	camera.fov = 55.0
	scene.add_child(camera)
	camera.make_current()
	# From over the harbour, looking south at the CBD skyline.
	camera.global_position = Vector3(350.0, 60.0, -2100.0)
	camera.look_at(Vector3(-150.0, 60.0, -400.0), Vector3.UP)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/captures/l89/skyline_roofline_night.png")
	print("CAPTURED skyline_roofline_night")
	# Aerial rooftop view showing the clutter up close.
	camera.global_position = Vector3(-260.0, 95.0, -700.0)
	camera.look_at(Vector3(-120.0, 30.0, -460.0), Vector3.UP)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/captures/l89/rooftop_clutter_aerial.png")
	print("CAPTURED rooftop_clutter_aerial")
	quit(0)
