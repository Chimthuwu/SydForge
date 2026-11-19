extends SceneTree

## Phase 6A harbour water captures — windowed run only (images need a renderer).
##
## Captures the required viewpoints: Circular Quay, Opera House, Harbour Bridge
## over water, Farm Cove, Woolloomooloo Bay, Darling Harbour, Barangaroo and two
## aerials. Set SPLOOGE_CAPTURE_PREFIX to rename the output files (used to keep
## "before" copies); default prefix is "phase6a_".

var world: Node3D
var prefix := "phase6a_"


func _initialize() -> void:
	var env_prefix := OS.get_environment("SPLOOGE_CAPTURE_PREFIX")
	if not env_prefix.is_empty():
		prefix = env_prefix
	call_deferred("run")


func capture(label: String, pos: Vector3, target: Vector3, fov := 60.0) -> void:
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = pos
	camera.fov = fov
	camera.far = 6000
	camera.near = 0.3
	camera.look_at(target)
	camera.current = true
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/%s%s.png" % [prefix, label])
	print("CAPTURE ", label)
	camera.queue_free()


func run() -> void:
	world = load("res://sydney/sydney_test.tscn").instantiate()
	root.add_child(world)
	for i in 200:
		await process_frame
	world.rig.set_process(false)
	print("WORLD BUILD ", world.sydney_world.build_times_ms)
	await capture("quay_east", Vector3(219.9, 3.0, -1755.7), Vector3(658.0, 10.0, -1763.0), 60.0)
	await capture("quay_west", Vector3(219.9, 3.0, -1755.7), Vector3(-300.0, 0.0, -1830.0), 60.0)
	await capture("opera_north", Vector3(632.0, 10.0, -1650.9), Vector3(247.3, 60.0, -2299.6), 62.0)
	await capture("bridge_water", Vector3(450.0, 58.0, -2200.0), Vector3(200.0, 0.0, -2450.0), 62.0)
	await capture("farm_cove", Vector3(640.0, 25.0, -1560.0), Vector3(800.0, 0.0, -1720.0), 62.0)
	await capture("woolloomooloo", Vector3(620.0, 60.0, -1500.0), Vector3(1000.0, 0.0, -1650.0), 62.0)
	await capture("darling", Vector3(-250.0, 160.0, 100.0), Vector3(-650.0, 0.0, -280.0), 62.0)
	await capture("barangaroo", Vector3(150.0, 130.0, -1550.0), Vector3(-150.0, 0.0, -1830.0), 62.0)
	await capture("aerial", Vector3(250.0, 600.0, -1100.0), Vector3(250.0, 0.0, -2100.0), 70.0)
	await capture("aerial_west", Vector3(-350.0, 450.0, 150.0), Vector3(-650.0, 0.0, -250.0), 70.0)
	world.queue_free()
	await process_frame
	quit()
