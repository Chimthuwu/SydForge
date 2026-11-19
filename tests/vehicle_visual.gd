extends SceneTree

## Vehicle visual verification — windowed run. Set SPLOOGE_CAPTURE_PREFIX to
## rename the output files; default "vehicle_".
##   ./Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/vehicle_visual.gd

var world: Node3D
var prefix := "vehicle_"


func _initialize() -> void:
	var env_prefix := OS.get_environment("SPLOOGE_CAPTURE_PREFIX")
	if not env_prefix.is_empty():
		prefix = env_prefix
	call_deferred("run")


func capture(label: String, pos: Vector3, target: Vector3, fov := 70.0) -> void:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = pos
	camera.fov = fov
	camera.far = 6000
	camera.look_at(target)
	camera.current = true
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/%s%s.png" % [prefix, label])
	print("CAPTURE ", label)
	camera.queue_free()


func run() -> void:
	world = load("res://scenes/district.tscn").instantiate()
	root.add_child(world)
	for i in 220:
		await process_frame
	world.rig.set_process(false)
	var car: ArcadeCar = world.vehicles[0]
	car.enter(world.player)
	print("CAR ", car.vehicle_name, " spawn=", car.position, " top_speed=", car.top_speed)

	## 1. Boosted drive high above the middle of the map.
	Input.action_press("sprint")
	Input.action_press("forward")
	for i in 200:
		await physics_frame
	capture("boosted_drive", Vector3(6, 50, 60), Vector3(0, 12, -20), 62.0)
	Input.action_release("sprint")

	## 2. Powerslide drift: right hand, released boost.
	Input.action_press("jump")
	Input.action_press("right")
	for i in 90:
		await physics_frame
	capture("drift_mid", Vector3(-2, 30, 10), Vector3(-5, 4, 10), 62.0)
	for i in 120:
		await physics_frame
	capture("drift_recovered", Vector3(6, 40, 40), Vector3(0, 6, 8), 62.0)
	Input.action_release("jump")
	Input.action_release("right")

	## 3. Skid marks after cornering at speed.
	Input.action_press("forward")
	for i in 30:
		await physics_frame
	Input.action_press("right")
	for i in 70:
		await physics_frame
	Input.action_release("right")
	await frames(40)
	Input.action_release("forward")
	capture("skid_marks", Vector3(3, 18, 30), Vector3(0, 6, 50), 55.0)

	world.queue_free()
	await process_frame
	quit()


func frames(count: int) -> void:
	for i in count:
		await physics_frame
