extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	for i in 90:
		await process_frame
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20,0)
	var old_yaw: float = world.rig.yaw
	root.push_input(motion)
	await process_frame
	print("VISUAL mouse event changes yaw: ",world.rig.yaw != old_yaw)
	world.rig.yaw = 0
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/street.png")
	var car: ArcadeCar = world.vehicles[0]
	car.position.x = 0
	world.player.position = car.position+Vector3(2.5,0,0)
	for i in 5:
		await physics_frame
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.keycode = KEY_E
	interact.pressed = true
	root.push_input(interact)
	await process_frame
	print("VISUAL interact event enters vehicle: ",world.player.vehicle == car)
	Input.action_press("forward")
	for i in 50:
		await physics_frame
	Input.action_release("forward")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/driving.png")
	print("VISUAL driving speed: ",car.speed)
	Input.action_press("jump")
	for i in 60:
		await physics_frame
	Input.action_release("jump")
	root.push_input(interact)
	await process_frame
	print("VISUAL interact event exits vehicle: ",world.player.vehicle == null)
	world.player.position = Vector3(0,0.1,40)
	world.player.velocity = Vector3.ZERO
	world.enemy.set_physics_process(false)
	world.enemy.position = Vector3(0.8,0.1,25)
	world.rig.yaw = 0
	world.rig.pitch = 0
	for i in 50:
		await physics_frame
	Input.action_press("fire")
	for i in 2:
		await physics_frame
	Input.action_release("fire")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/combat.png")
	print("VISUAL firing input damages enemy: ",world.enemy.health == 75)
	world.rig.set_process(false)
	var overview := Camera3D.new()
	world.add_child(overview)
	overview.global_position = Vector3(-100,125,150)
	overview.look_at(Vector3(0,0,0))
	overview.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/overview.png")
	print("VISUAL captures saved")
	world.queue_free()
	await process_frame
	quit()
