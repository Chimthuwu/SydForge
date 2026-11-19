extends SceneTree

var game: Variant


func _initialize() -> void:
	call_deferred("run")


func frames(count: int) -> void:
	for _index in count:
		await physics_frame


func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://tests/" + name
	var error := image.save_png(path)
	print("CAPTURE: ", path, " error=", error, " size=", image.get_size())


func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(150)

	var player: BoomPlayer = game.player
	var camera: BoomCamera = game.rig
	await capture("main_first_person.png")
	camera.show_muzzle_flash()
	await capture("main_first_person_weapon.png")

	# Use the production possession/physics path to capture a short drive.
	var sport: ArcadeCar = game.vehicles[1]
	game.interact()
	await frames(55)
	Input.action_press("forward")
	await frames(35)
	Input.action_release("forward")
	Input.action_press("jump")
	await frames(35)
	Input.action_release("jump")
	await frames(10)
	camera.manual_look_time = 2.0
	await capture("main_third_person_vehicle.png")

	if sport.driver != null:
		sport.exit_vehicle()
	await frames(70)
	await capture("main_exit_first_person.png")

	game.queue_free()
	await process_frame
	quit()
