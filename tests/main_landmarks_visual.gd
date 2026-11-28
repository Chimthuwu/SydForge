extends SceneTree

var game: Node3D
var camera: Camera3D


func _initialize() -> void:
	call_deferred("run")


func settle(count: int) -> void:
	for _index in count:
		await process_frame


func capture(label: String, position: Vector3, target: Vector3, fov: float = 58.0) -> void:
	camera.position = position
	camera.fov = fov
	camera.look_at(target)
	camera.current = true
	await settle(8)
	var query := PhysicsRayQueryParameters3D.create(position, target, 1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	print("VIEW: ", label, " from=", position, " target=", target,
		" obstruction=", hit.get("collider").name if not hit.is_empty() else "none",
		" at=", hit.get("position") if not hit.is_empty() else Vector3.ZERO)
	await RenderingServer.frame_post_draw
	var path := "res://tests/landmark_" + label + ".png"
	var error := root.get_texture().get_image().save_png(path)
	print("CAPTURE: ", path, " error=", error)


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await settle(4)
	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 2800.0
	game.add_child(camera)
	camera.current = true

	await capture("town_hall", Vector3(-166.1, 2.0, -14.0), Vector3(-170.0, 52.0, 22.0), 48.0)
	await capture("queen_victoria_building", Vector3(-170.0, 60.0, -190.0), Vector3(-121.0, 24.0, -137.0), 52.0)
	await capture("st_marys_cathedral", Vector3(440.0, 2.0, -190.0), Vector3(500.0, 82.0, -195.0), 50.0)
	await capture("hyde_park", Vector3(332.0, 3.0, -60.0), Vector3(332.0, 5.0, -178.0), 54.0)
	await capture("central_station", Vector3(-150.0, 150.0, 1170.0), Vector3(-180.0, 12.0, 1060.0), 60.0)
	await capture("sydney_tower_quay", Vector3(420.0, 45.0, -1400.0), Vector3(166.0, 240.0, -230.0), 46.0)
	await capture("sydney_tower_street", Vector3(332.0, 3.0, -60.0), Vector3(166.0, 250.0, -230.0), 58.0)
	await capture("circular_quay", Vector3(280.0, 12.0, -1500.0), Vector3(280.0, 12.0, -1375.0), 54.0)
	await capture("darling_harbour", Vector3(-695.0, 12.0, -270.0), Vector3(-540.0, 6.0, -242.0), 54.0)
	await capture("pyrmont_bridge", Vector3(-695.0, 12.0, -270.0), Vector3(-800.0, 7.0, -290.0), 52.0)

	game.queue_free()
	await process_frame
	quit()
