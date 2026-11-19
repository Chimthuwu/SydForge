extends SceneTree

## Rendered captures of the Sydney Opera House inside the real Sydney world.
##   SPLOOGE_SYDNEY=1 ./Godot_v4.7.2-stable_win64_console.exe --path . \
##       --script res://tests/opera_house_visual.gd

var world: Node3D


func _initialize() -> void:
	call_deferred("run")


func _capture(camera: Camera3D, path: String, label: String) -> void:
	camera.current = true
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("VISUAL captured: ", label, " -> ", path)


func _camera(position: Vector3, target: Vector3, fov: float = 55.0) -> Camera3D:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = position
	camera.fov = fov
	camera.near = 0.2
	camera.far = 5000.0
	camera.look_at(target, Vector3.UP)
	return camera


func run() -> void:
	world = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	for i in 90:
		await process_frame
	print("VISUAL using_sydney: ", world.using_sydney)
	if not world.using_sydney:
		push_error("VISUAL: run with SPLOOGE_SYDNEY=1")
		quit(2)
		return
	var landmark = world.sydney_world.get_node_or_null("OperaHouse")
	print("VISUAL landmark present: ", landmark != null)
	if landmark != null:
		print("VISUAL landmark stats: ", landmark.stats)
	print("VISUAL build_times_ms: ", world.sydney_world.build_times_ms)
	print("VISUAL geometry_counts: ", world.sydney_world.geometry_counts)

	# Bennelong Point: podium centroid (658.72, -1763.81), north = -Z.
	var centre := Vector3(658.72, 0.0, -1763.81)
	world.rig.set_process(false)

	await _capture(
		_camera(centre + Vector3(120.0, 175.0, 225.0), centre + Vector3(0.0, 26.0, -12.0), 52.0),
		"res://tests/opera_aerial.png",
		"aerial overview"
	)
	await _capture(
		_camera(centre + Vector3(-26.0, 16.0, -150.0), centre + Vector3(0.0, 40.0, 0.0), 55.0),
		"res://tests/opera_harbour.png",
		"harbour-facing view"
	)
	await _capture(
		_camera(centre + Vector3(-40.0, 2.6, 118.0), centre + Vector3(0.0, 30.0, 0.0), 62.0),
		"res://tests/opera_forecourt.png",
		"foreshore / forecourt"
	)
	await _capture(
		_camera(Vector3(712.0, 96.0, -1694.0), Vector3(642.0, 46.0, -1782.0), 52.0),
		"res://tests/opera_roof_detail.png",
		"close-up roof shells"
	)
	await _capture(
		_camera(Vector3(318.0, 52.0, -1596.0), centre + Vector3(0.0, 34.0, 0.0), 36.0),
		"res://tests/opera_circular_quay.png",
		"Circular Quay approach"
	)

	print("VISUAL done")
	world.queue_free()
	await process_frame
	quit()
